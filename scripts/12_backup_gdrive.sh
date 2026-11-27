#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD MODULE: [12] Automated Google Drive Backup Engine
# Version:          1.9.1 (Security Audit Hardened: Fail-Loud Missing State Guard,
#                   Minimum Snapshot Count Retention (MIN_KEEP=3), Zero-Root-Chown
#                   Tier-2 DB Fallback, Control-Plane Config Archive, Octal-Safe)
# Architecture:     Interactive TUI & Headless Cron | Disaster Recovery Suite
# Platform:         Debian 11/12/13, Ubuntu 22.04/24.04/26.04 LTS
# ==============================================================================
set -euo pipefail

ESC=$(printf '\033')
B_O=$(printf '\133')
B_C=$(printf '\135')

# ------------------------------------------------------------------------------
# 1. TERMINAL THEME & ABSOLUTE CURSOR POSITIONING (TTY-SAFE)
# ------------------------------------------------------------------------------
NON_INTERACTIVE=0
if [[ "${1:-}" == "--non-interactive" ]]; then
    NON_INTERACTIVE=1
fi

if [ "$NON_INTERACTIVE" -eq 0 ] && tput setaf 1 >/dev/null 2>&1; then
    RED=$(tput setaf 1);    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4)
    PURPLE=$(tput setaf 5); CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7);  GRAY=$(tput setaf 8 2>/dev/null || tput setaf 7)
    BOLD=$(tput bold);      NC=$(tput sgr0)
else
    RED="${ESC}${B_O}0;31m";    GREEN="${ESC}${B_O}0;32m"
    YELLOW="${ESC}${B_O}1;33m"; BLUE="${ESC}${B_O}0;34m"
    PURPLE="${ESC}${B_O}0;35m"; CYAN="${ESC}${B_O}0;36m"
    WHITE="${ESC}${B_O}1;37m";  GRAY="${ESC}${B_O}0;90m"
    BOLD="${ESC}${B_O}1m";      NC="${ESC}${B_O}0m"
fi

if [ "$NON_INTERACTIVE" -eq 0 ] && tput hpa 47 >/dev/null 2>&1; then
    COL_MID=$(tput hpa 47)
else
    COL_MID="${ESC}${B_O}48G"
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ [FATAL] This module must be executed as root.${NC}" >&2
    exit 1
fi

if [ "$NON_INTERACTIVE" -eq 1 ] && [ -f "/var/log/bashboard_backup.log" ] && [ ! -L "/var/log/bashboard_backup.log" ]; then
    chmod 600 /var/log/bashboard_backup.log 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 2. PERSISTENT CONFIGURATION, RUNTIME DEPENDENCY & RCLONE REMOTE ASSERTION
# ------------------------------------------------------------------------------
readonly SELF_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/$(basename "${BASH_SOURCE[0]}")"
readonly BACKUP_CONF="/etc/bashboard/backup.conf"
readonly STAGING_VAULT="/var/backups/bashboard/gdrive-staging"
readonly BACKUP_LOCK="/run/bashboard_backup.lock"
readonly DISABLED_CLI_FUNCS="exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec,pcntl_fork,pcntl_signal,pcntl_alarm,dl,putenv,show_source,highlight_file,proc_get_status,opcache_get_status,opcache_get_configuration,posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,posix_setuid,posix_geteuid,posix_getpwuid"

RCLONE_REMOTE="bashboard-gdrive"
RETENTION_DAYS=14
MIN_KEEP_SNAPSHOTS=3
BACKUP_FILES=1
BACKUP_DATABASES=1

export HOME="${HOME:-/root}"

load_backup_conf() {
    if [ -f "$BACKUP_CONF" ] && [ ! -L "$BACKUP_CONF" ] && [ "$(stat -c '%u' "$BACKUP_CONF" 2>/dev/null)" = "0" ]; then
        local v_rem v_ret v_min v_db v_fl
        v_rem=$(grep -E '^RCLONE_REMOTE=' "$BACKUP_CONF" 2>/dev/null | cut -d'=' -f2- || true)
        v_ret=$(grep -E '^RETENTION_DAYS=' "$BACKUP_CONF" 2>/dev/null | cut -d'=' -f2- || true)
        v_min=$(grep -E '^MIN_KEEP_SNAPSHOTS=' "$BACKUP_CONF" 2>/dev/null | cut -d'=' -f2- || true)
        v_db=$(grep -E '^BACKUP_DATABASES=' "$BACKUP_CONF" 2>/dev/null | cut -d'=' -f2- || true)
        v_fl=$(grep -E '^BACKUP_FILES=' "$BACKUP_CONF" 2>/dev/null | cut -d'=' -f2- || true)

        [[ "$v_rem" =~ ^[a-zA-Z0-9_.-]+$ ]] && RCLONE_REMOTE="$v_rem"
        [[ "$v_ret" =~ ^[0-9]+$ ]] && [ "$((10#$v_ret))" -ge 1 ] && RETENTION_DAYS=$((10#$v_ret))
        [[ "$v_min" =~ ^[0-9]+$ ]] && [ "$((10#$v_min))" -ge 1 ] && MIN_KEEP_SNAPSHOTS=$((10#$v_min))
        [[ "$v_db" =~ ^[01]$ ]] && BACKUP_DATABASES="$v_db"
        [[ "$v_fl" =~ ^[01]$ ]] && BACKUP_FILES="$v_fl"
    fi
}

save_backup_conf() {
    mkdir -p -m 0700 /etc/bashboard
    (
        umask 077
        cat > "$BACKUP_CONF" <<EOF
RCLONE_REMOTE=${RCLONE_REMOTE}
RETENTION_DAYS=${RETENTION_DAYS}
MIN_KEEP_SNAPSHOTS=${MIN_KEEP_SNAPSHOTS}
BACKUP_DATABASES=${BACKUP_DATABASES}
BACKUP_FILES=${BACKUP_FILES}
EOF
        chown root:root "$BACKUP_CONF"
        chmod 600 "$BACKUP_CONF"
    )
}

load_backup_conf

ensure_rclone() {
    if ! command -v rclone >/dev/null 2>&1; then
        echo -e "${YELLOW}rclone is not installed. Installing official binary...${NC}"
        curl -fsSL https://rclone.org/install.sh | bash >/dev/null 2>&1 || {
            echo -e "${RED}❌ Failed to install rclone. Install manually and re-run.${NC}" >&2
            exit 1
        }
        echo -e "${GREEN}✅ rclone successfully installed.${NC}"
    fi
}
ensure_rclone

has_rclone_remote() {
    sed -i '/^client_id = [nN]$/d; /^client_secret = [nN]$/d' /root/.config/rclone/rclone.conf 2>/dev/null || true
    rclone listremotes 2>/dev/null | grep -qx "${RCLONE_REMOTE}:"
}

check_rclone_remote() {
    if has_rclone_remote; then
        echo -e "${GREEN}● READY (${RCLONE_REMOTE})${NC}"
    else
        echo -e "${RED}○ NOT CONFIGURED${NC}"
    fi
}

toggle_status() {
    local val="$1"
    if [ "$val" -eq 1 ]; then
        echo -e "${GREEN}[✔] ENABLED ${NC}"
    else
        echo -e "${GRAY}[ ] DISABLED${NC}"
    fi
}

# ------------------------------------------------------------------------------
# 3. TUI CONFIGURATOR INTERFACE
# ------------------------------------------------------------------------------
draw_backup_tui() {
    clear
    local remote_status
    remote_status=$(check_rclone_remote)

    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Module: %-25s${NC}\n" "BASHBOARD BACKUP SUITE (V1.9.1)" "Google Drive Sync Engine"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   📋 ${PURPLE}${BOLD}OFF-SITE DISASTER RECOVERY & CLOUD SYNC MATRIX${NC}"
    echo -e "      Per-site streaming engine + Server Config archive (Always preserves >= ${MIN_KEEP_SNAPSHOTS} snapshots)."
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    printf "      %-24s: %-26b ${COL_MID}${GRAY}│${NC} Action   : ${CYAN}[1] Configure Remote${NC}\n" "Google Drive Remote" "$remote_status"
    printf "   ${CYAN}[2]${NC} %b %-20s ${COL_MID}${GRAY}│${NC} Mode     : ${WHITE}--single-transaction${NC}\n" "$(toggle_status "$BACKUP_DATABASES")" "MySQL Databases"
    printf "   ${CYAN}[3]${NC} %b %-20s ${COL_MID}${GRAY}│${NC} Payload  : ${WHITE}/var/www/*/public_html${NC}\n" "$(toggle_status "$BACKUP_FILES")" "Web Application Files"
    printf "   ${CYAN}[4]${NC} %-24s: ${YELLOW}%-22s${NC} ${COL_MID}${GRAY}│${NC} Min Keep : ${GREEN}%s Snapshots${NC}\n" "Retention Window" "${RETENTION_DAYS} Days" "$MIN_KEEP_SNAPSHOTS"

    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ${GREEN}${BOLD}[9] ⚡ EXECUTE BACKUP & STREAM TO GOOGLE DRIVE NOW${NC}"
    echo -e "   ${CYAN}${BOLD}[8] ⏱️  INSTALL DAILY AUTOMATED CRONTAB (03:00 AM)${NC}"
    echo -e "   ${RED}${BOLD}[0] ↩️  CANCEL AND RETURN TO BASHBOARD${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# ------------------------------------------------------------------------------
# 4. CONFIGURATION INPUT LOOP (SKIPPED IN HEADLESS CRON MODE)
# ------------------------------------------------------------------------------
if [ "$NON_INTERACTIVE" -eq 0 ]; then
    while true; do
        draw_backup_tui
        tput cnorm 2>/dev/null || true
        echo -ne "\n   ${BOLD}${WHITE}Choose an action [0-9]:${NC} "
        read -r opt || opt="0"

        case "$opt" in
            1)
                clear
                echo -e "${CYAN}==================================================================${NC}"
                echo -e "   🌐 ${BOLD}${WHITE}Interactive Google Drive Remote Setup (rclone)${NC}"
                echo -e "${CYAN}==================================================================${NC}"
                echo -e "   1. Choose 'n' for new remote."
                echo -e "   2. Name the remote: ${YELLOW}${RCLONE_REMOTE}${NC}"
                echo -e "   3. Type of storage: choose 'drive' (Google Drive)."
                echo -e "   4. Leave client_id & client_secret blank (Press Enter)."
                echo -e "   🔐 Security Tip: Wrap with an 'rclone crypt' remote for client-side E2EE."
                echo -e "${CYAN}------------------------------------------------------------------${NC}\n"
                rclone config
                continue
                ;;
            2) BACKUP_DATABASES=$(( 1 - BACKUP_DATABASES )); save_backup_conf ;;
            3) BACKUP_FILES=$(( 1 - BACKUP_FILES )); save_backup_conf ;;
            4)
                echo ""
                read -rp "   Enter Cloud Retention Days (e.g., 7, 14, 30, 60): " user_ret
                if [[ "$user_ret" =~ ^[0-9]+$ ]] && [ "$((10#$user_ret))" -ge 1 ]; then
                    RETENTION_DAYS=$((10#$user_ret))
                    save_backup_conf
                fi
                ;;
            8)
                if ! has_rclone_remote; then
                    echo -e "\n   ${RED}❌ Configure Google Drive remote '${RCLONE_REMOTE}' [Option 1] before enabling cron!${NC}"
                    sleep 2
                    continue
                fi
                save_backup_conf
                cron_job_file="/etc/cron.d/bashboard-gdrive-backup"
                cat > "$cron_job_file" <<EOF
# Bashboard Automated Google Drive Off-Site Backup Engine
# Runs nightly at 03:00 AM strictly as root (settings persisted in /etc/bashboard/backup.conf)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
HOME=/root

0 3 * * * root umask 077; /bin/bash "$SELF_PATH" --non-interactive >/var/log/bashboard_backup.log 2>&1
EOF
                chmod 644 "$cron_job_file"
                echo -e "\n   ${GREEN}✅ Nightly crontab installed & settings saved to ${BACKUP_CONF} (Retention: ${RETENTION_DAYS}d | Min Keep: ${MIN_KEEP_SNAPSHOTS}).${NC}"
                sleep 2
                ;;
            9)
                if ! has_rclone_remote; then
                    echo -e "\n   ${RED}❌ Google Drive remote '${RCLONE_REMOTE}' is not configured! Press [1] first.${NC}"
                    sleep 2
                    continue
                fi
                if [ "$BACKUP_DATABASES" -eq 0 ] && [ "$BACKUP_FILES" -eq 0 ]; then
                    echo -e "\n   ${YELLOW}Both Databases and Files are disabled! Enable at least one.${NC}"
                    sleep 1.5
                    continue
                fi
                save_backup_conf
                break
                ;;
            0)
                echo -e "\n   ${GREEN}Returning to Bashboard...${NC}"
                exit 0
                ;;
            *)
                echo -e "\n   ${RED}Invalid option!${NC}"
                sleep 0.8
                ;;
        esac
    done
    clear
else
    if ! has_rclone_remote; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [FATAL] rclone remote '${RCLONE_REMOTE}' is not configured. Aborting backup." >&2
        exit 1
    fi
fi

# ==============================================================================
# 5. EXECUTION PHASE: EXCLUSIVE FLOCK & PER-SITE STREAMING BACKUP ENGINE
# ==============================================================================
if [ -L "$BACKUP_LOCK" ]; then
    echo -e "${RED}❌ [SECURITY] Backup lock file is a symlink! Aborting.${NC}" >&2
    exit 1
fi

old_umask=$(umask)
umask 077
exec 201>>"$BACKUP_LOCK"
umask "$old_umask"

if ! flock -n 201; then
    echo -e "${RED}❌ [ABORT] Another backup process is currently running.${NC}" >&2
    exit 1
fi

TIMESTAMP=$(date +'%Y-%m-%d_%H%M%S')
REMOTE_DEST="${RCLONE_REMOTE}:bashboard-backups/${TIMESTAMP}"

echo -e "${CYAN}==================================================================${NC}"
echo -e "   🚀 ${BOLD}${WHITE}Executing Per-Site Streaming Backup to Google Drive...${NC}"
echo -e "   ☁️  Remote Target: ${YELLOW}${REMOTE_DEST}${NC}"
echo -e "${CYAN}==================================================================${NC}\n"

mkdir -p "$STAGING_VAULT"
chmod 700 "$STAGING_VAULT"

cleanup_staging() {
    rm -rf "${STAGING_VAULT:?}"/*
}
trap cleanup_staging EXIT

DUMP_BIN="mariadb-dump"
command -v mariadb-dump >/dev/null 2>&1 || DUMP_BIN="mysqldump"

UPLOADED_COUNT=0
FAILED_COUNT=0

# Helper: Stream a single artifact to Google Drive and immediately reclaim local staging space
stream_and_purge_artifact() {
    local artifact_path="$1"
    local artifact_name
    artifact_name=$(basename "$artifact_path")

    local copy_ok=0
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        rclone copy "$artifact_path" "$REMOTE_DEST" && copy_ok=1
    else
        rclone copy "$artifact_path" "$REMOTE_DEST" --progress && copy_ok=1
    fi

    if [ "$copy_ok" -eq 1 ]; then
        UPLOADED_COUNT=$((UPLOADED_COUNT + 1))
        rm -f "$artifact_path"
        echo -e "   ${GREEN}☁️  Streamed & cleaned local cache:${NC} ${artifact_name}"
        return 0
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        rm -f "$artifact_path"
        echo -e "   ${RED}❌ [ERROR] Cloud upload failed for:${NC} ${artifact_name}" >&2
        return 1
    fi
}

# Helper: Symlink-Safe Tier-2 DB Dump Fallback (Zero root mkdir/chown inside tenant tmp/)
tier2_wp_db_dump() {
    local domain="$1"
    local vd="$2"
    local vhost_user="$3"
    local php_ver="$4"
    local db_name="$5"
    local dump_file="$6"

    command -v wp >/dev/null 2>&1 || return 1
    [[ "$vhost_user" =~ ^v_[a-z0-9_]+$ ]] && [ "$vhost_user" != "v_pma_sys" ] || return 1

    local user_home
    user_home=$(getent passwd "$vhost_user" 2>/dev/null | cut -d: -f6 || true)
    [[ "$user_home" == "/var/www/$domain" ]] || return 1

    local wp_target="$vd/public_html"
    [[ -f "$vd/public_html/core/wp-settings.php" ]] && wp_target="$vd/public_html/core"
    [ -f "$wp_target/wp-config.php" ] || [ -f "$vd/public_html/wp-config.php" ] || return 1

    local site_php="php"
    [[ "$php_ver" =~ ^[0-9]+\.[0-9]+$ && -x "/usr/bin/php${php_ver}" ]] && site_php="/usr/bin/php${php_ver}"

    local site_tmp="/var/www/${domain}/tmp"
    [ -d "$site_tmp" ] && [ ! -L "$site_tmp" ] || return 1
    # Strictly create cache subdir as unprivileged tenant user (Zero root chown inside tmp/)
    runuser -u "$vhost_user" -- mkdir -p "$site_tmp/wp-cache" 2>/dev/null || true

    local open_base="/var/www/${domain}/:/usr/local/bin/wp:/usr/share/zoneinfo/:/dev/urandom"

    local site_db_user site_db_pass site_db_host
    site_db_user=$(runuser -u "$vhost_user" -- env HOME="/var/www/$domain" TMPDIR="$site_tmp" WP_CLI_CACHE_DIR="$site_tmp/wp-cache" \
        "$site_php" -d display_errors=0 -d sys_temp_dir="$site_tmp" -d open_basedir="$open_base" -d disable_functions="${DISABLED_CLI_FUNCS}" \
        /usr/local/bin/wp config get DB_USER --path="$wp_target" --skip-plugins --skip-themes 2>/dev/null || true)
    site_db_pass=$(runuser -u "$vhost_user" -- env HOME="/var/www/$domain" TMPDIR="$site_tmp" WP_CLI_CACHE_DIR="$site_tmp/wp-cache" \
        "$site_php" -d display_errors=0 -d sys_temp_dir="$site_tmp" -d open_basedir="$open_base" -d disable_functions="${DISABLED_CLI_FUNCS}" \
        /usr/local/bin/wp config get DB_PASSWORD --path="$wp_target" --skip-plugins --skip-themes 2>/dev/null || true)
    site_db_host=$(runuser -u "$vhost_user" -- env HOME="/var/www/$domain" TMPDIR="$site_tmp" WP_CLI_CACHE_DIR="$site_tmp/wp-cache" \
        "$site_php" -d display_errors=0 -d sys_temp_dir="$site_tmp" -d open_basedir="$open_base" -d disable_functions="${DISABLED_CLI_FUNCS}" \
        /usr/local/bin/wp config get DB_HOST --path="$wp_target" --skip-plugins --skip-themes 2>/dev/null || echo "localhost")

    [[ -n "$site_db_user" && -n "$site_db_pass" ]] || return 1

    local dump_conn_args=()
    local db_host_part="${site_db_host%%:*}"
    local db_extra_part=""
    [[ "$site_db_host" == *:* ]] && db_extra_part="${site_db_host#*:}"

    dump_conn_args+=( -h "${db_host_part:-localhost}" )
    if [[ "$db_extra_part" =~ ^[0-9]+$ ]]; then
        dump_conn_args+=( -P "$db_extra_part" )
    elif [[ "$db_extra_part" == /* ]]; then
        dump_conn_args+=( -S "$db_extra_part" )
    fi

    MYSQL_PWD="$site_db_pass" "$DUMP_BIN" --single-transaction --quick --routines --triggers \
        "${dump_conn_args[@]}" -u "$site_db_user" "$db_name" 2>/dev/null | gzip -c > "$dump_file"
}

shopt -s nullglob
vhost_dirs=( /var/www/* )
shopt -u nullglob

# 5.1 Per-Site Non-Locking Database Dump & Immediate Cloud Stream (Fail-Loud on Missing State)
if [ "$BACKUP_DATABASES" -eq 1 ]; then
    echo -e "${BLUE}--- [1/3] Dumping & Streaming MariaDB Databases (Non-Locking InnoDB) ---${NC}"

    for vd in "${vhost_dirs[@]}"; do
        [ -d "$vd" ] || continue
        domain=$(basename "$vd")
        [[ "$domain" == "html" || "$domain" == "_acme-challenge" ]] && continue
        [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$ ]] || continue

        has_wp=0
        if [[ -f "$vd/public_html/wp-config.php" || -f "$vd/public_html/core/wp-config.php" ]]; then
            has_wp=1
        fi

        sf=""
        if [ -f "/etc/bashboard/sites/${domain}.state" ] && [ ! -L "/etc/bashboard/sites/${domain}.state" ]; then
            sf="/etc/bashboard/sites/${domain}.state"
        elif [ -f "$vd/.bashboard-state" ] && [ ! -L "$vd/.bashboard-state" ] && [ "$(stat -c '%u' "$vd/.bashboard-state" 2>/dev/null)" = "0" ]; then
            sf="$vd/.bashboard-state"
        fi

        if [[ -z "$sf" ]]; then
            # Fail loudly if a real site lacks an authoritative state manifest (blocks silent pruning!)
            if [ -d "$vd/public_html" ]; then
                FAILED_COUNT=$((FAILED_COUNT + 1))
                echo -e "   ${RED}❌ [ERROR] Missing root-owned state manifest for '${domain}'. Marking backup incomplete to protect remote history.${NC}" >&2
            fi
            continue
        fi

        db_name=$(grep -E "^DB_NAME=" "$sf" 2>/dev/null | cut -d'=' -f2- || true)
        vhost_user=$(grep -E "^TENANT_USER=" "$sf" 2>/dev/null | cut -d'=' -f2- || true)
        site_php_ver=$(grep -E "^PHP_VER=" "$sf" 2>/dev/null | cut -d'=' -f2- || true)

        if [[ -z "$db_name" ]]; then
            # Blank non-WP site has empty DB_NAME legitimately; WordPress site without DB_NAME is an error
            if [ "$has_wp" -eq 1 ]; then
                FAILED_COUNT=$((FAILED_COUNT + 1))
                echo -e "   ${RED}❌ [ERROR] WordPress site '${domain}' has empty DB_NAME in state manifest!${NC}" >&2
            fi
            continue
        fi

        if [[ ! "$db_name" =~ ^[a-zA-Z0-9_]{1,64}$ ]]; then
            FAILED_COUNT=$((FAILED_COUNT + 1))
            echo -e "   ${RED}❌ [ERROR] Invalid DB_NAME '${db_name}' in state manifest for '${domain}'!${NC}" >&2
            continue
        fi

        dump_file="${STAGING_VAULT}/${domain}_db_${TIMESTAMP}.sql.gz"
        echo -e "   Dumping database \`${YELLOW}$db_name\` (Site: $domain)..."

        dump_ok=0
        if "$DUMP_BIN" --single-transaction --quick --routines --triggers -u root "$db_name" 2>/dev/null | gzip -c > "$dump_file"; then
            if [ -f "$dump_file" ] && [ "$(stat -c '%s' "$dump_file" 2>/dev/null || echo 0)" -gt 64 ]; then
                dump_ok=1
            fi
        fi

        if [ "$dump_ok" -eq 0 ]; then
            rm -f "$dump_file"
            if tier2_wp_db_dump "$domain" "$vd" "$vhost_user" "$site_php_ver" "$db_name" "$dump_file"; then
                if [ -f "$dump_file" ] && [ "$(stat -c '%s' "$dump_file" 2>/dev/null || echo 0)" -gt 64 ]; then
                    dump_ok=1
                fi
            fi
        fi

        if [ "$dump_ok" -eq 1 ]; then
            chmod 600 "$dump_file"
            stream_and_purge_artifact "$dump_file" || true
        else
            rm -f "$dump_file"
            FAILED_COUNT=$((FAILED_COUNT + 1))
            echo -e "   ${RED}⚠️  [WARNING] Failed to dump database '$db_name' for $domain.${NC}" >&2
        fi
    done
fi

# 5.2 Per-Site Web Asset Archiving & Immediate Cloud Stream
if [ "$BACKUP_FILES" -eq 1 ]; then
    echo -e "\n${BLUE}--- [2/3] Archiving & Streaming Web Payloads (Anchored Excludes) ---${NC}"

    for vd in "${vhost_dirs[@]}"; do
        [ -d "$vd/public_html" ] || continue
        domain=$(basename "$vd")
        [[ "$domain" == "html" || "$domain" == "_acme-challenge" ]] && continue
        [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$ ]] || continue

        tar_file="${STAGING_VAULT}/${domain}_web_${TIMESTAMP}.tar.gz"
        echo -e "   Archiving /var/www/$domain (Excluding root logs, tmp & cache)..."

        set +e
        tar -czf "$tar_file" \
            --exclude="${domain}/logs" \
            --exclude="${domain}/tmp" \
            --exclude="${domain}/public_html/wp-content/cache" \
            -C "/var/www" "$domain" 2>/dev/null
        tar_rc=$?
        set -e

        if [ "$tar_rc" -eq 0 ] || { [ "$tar_rc" -eq 1 ] && [ -s "$tar_file" ]; }; then
            chmod 600 "$tar_file"
            stream_and_purge_artifact "$tar_file" || true
        else
            rm -f "$tar_file"
            FAILED_COUNT=$((FAILED_COUNT + 1))
            echo -e "   ${RED}⚠️  [WARNING] Failed to archive web files for $domain (tar exit: ${tar_rc}).${NC}" >&2
        fi
    done
fi

# 5.3 Server Control-Plane Configuration Backup (VHosts, FPM Pools, State, Logrotate, Cron)
echo -e "\n${BLUE}--- [3/3] Archiving Server Control-Plane Configurations ---${NC}"
cfg_targets=()
[ -d "/etc/bashboard/sites" ] && cfg_targets+=( "/etc/bashboard/sites" )
[ -f "/etc/bashboard/backup.conf" ] && cfg_targets+=( "/etc/bashboard/backup.conf" )
[ -d "/etc/nginx/sites-available" ] && cfg_targets+=( "/etc/nginx/sites-available" )
[ -d "/etc/nginx/conf.d" ] && cfg_targets+=( "/etc/nginx/conf.d" )
shopt -s nullglob
for _p in /etc/php/*/fpm/pool.d /etc/logrotate.d/vhost-* /etc/cron.d/bashboard-*; do
    cfg_targets+=( "$_p" )
done
shopt -u nullglob

if [ ${#cfg_targets[@]} -gt 0 ]; then
    cfg_tar="${STAGING_VAULT}/server_configs_${TIMESTAMP}.tar.gz"
    if tar -czf "$cfg_tar" "${cfg_targets[@]}" 2>/dev/null && [ -s "$cfg_tar" ]; then
        chmod 600 "$cfg_tar"
        stream_and_purge_artifact "$cfg_tar" || true
    else
        rm -f "$cfg_tar"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        echo -e "   ${RED}⚠️  [WARNING] Failed to archive server control-plane configs.${NC}" >&2
    fi
fi

# 5.4 Zero-Loss Snapshot Pruning (Requires >=1 upload, 0 failures, AND always preserves newest MIN_KEEP_SNAPSHOTS)
prune_old_snapshots() {
    local cutoff_epoch=$(( $(date +%s) - (10#$RETENTION_DAYS * 86400) ))
    local snap_dirs=()
    local sd

    while IFS= read -r sd; do
        [[ "$sd" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$ ]] && snap_dirs+=("$sd")
    done < <(rclone lsf --dirs-only "${RCLONE_REMOTE}:bashboard-backups" 2>/dev/null | sed 's|/$||' | sort -r || true)

    local total_snaps=${#snap_dirs[@]}
    if [ "$total_snaps" -le "$MIN_KEEP_SNAPSHOTS" ]; then
        echo -e "   ${GRAY}Cloud snapshot count (${total_snaps}) <= minimum keep threshold (${MIN_KEEP_SNAPSHOTS}). Nothing pruned.${NC}"
        return 0
    fi

    local idx=0 pruned=0
    for sd in "${snap_dirs[@]}"; do
        idx=$((idx + 1))
        # Always preserve the newest MIN_KEEP_SNAPSHOTS regardless of age
        if [ "$idx" -le "$MIN_KEEP_SNAPSHOTS" ]; then
            continue
        fi

        local date_str="${sd:0:10} ${sd:11:2}:${sd:13:2}:${sd:15:2}"
        local snap_epoch
        snap_epoch=$(date -d "$date_str" +%s 2>/dev/null || echo 0)

        if [ "$snap_epoch" -gt 0 ] && [ "$snap_epoch" -lt "$cutoff_epoch" ]; then
            if rclone purge "${RCLONE_REMOTE}:bashboard-backups/${sd}" --drive-use-trash=false 2>/dev/null; then
                pruned=$((pruned + 1))
            fi
        fi
    done
    echo -e "   ${GREEN}✅ Cloud retention enforced: ${pruned} expired snapshot(s) purged (newest ${MIN_KEEP_SNAPSHOTS} always protected).${NC}"
}

if [ "$UPLOADED_COUNT" -gt 0 ] && [ "$FAILED_COUNT" -eq 0 ]; then
    echo -e "\n   ${GRAY}Evaluating remote snapshot retention (> ${RETENTION_DAYS}d, keeping >= ${MIN_KEEP_SNAPSHOTS} snapshots)...${NC}"
    prune_old_snapshots
else
    echo -e "\n   ${YELLOW}⚠️  [PRUNE GUARD] Skipping remote cloud pruning (Uploaded: ${UPLOADED_COUNT}, Failed: ${FAILED_COUNT}).${NC}" >&2
    if [ "$FAILED_COUNT" -gt 0 ]; then
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 6. FINAL SUMMARY REPORT (Never Claims Success on Zero Uploads)
# ------------------------------------------------------------------------------
if [ "$UPLOADED_COUNT" -eq 0 ]; then
    echo -e "\n${YELLOW}=================================================================="
    echo -e "   ⚠️  BACKUP COMPLETED WITH ZERO ARTIFACTS UPLOADED"
    echo -e "==================================================================${NC}"
    echo -e "   No eligible sites or configs were found to upload. Remote backups untouched."
    exit 1
fi

echo -e "\n${GREEN}=================================================================="
echo -e "   🎉 OFF-SITE BACKUP TO GOOGLE DRIVE FINISHED SUCCESSFULLY"
echo -e "==================================================================${NC}"
echo -e "Remote Destination : ${YELLOW}${REMOTE_DEST}${NC}"
echo -e "Artifacts Uploaded : ${GREEN}${UPLOADED_COUNT} files (0 failures)${NC}"
echo -e "Databases Dumped   : ${WHITE}$( [ "$BACKUP_DATABASES" -eq 1 ] && echo "Active (--single-transaction)" || echo "Skipped" )${NC}"
echo -e "Web Assets Staged  : ${WHITE}$( [ "$BACKUP_FILES" -eq 1 ] && echo "Active (Per-Site Streamed)" || echo "Skipped" )${NC}"
echo -e "Server Configs     : ${GREEN}Included (Nginx, FPM, State, Logrotate, Cron)${NC}"
echo -e "Remote Retention   : ${GREEN}${RETENTION_DAYS} Days (Min ${MIN_KEEP_SNAPSHOTS} snapshots always kept)${NC}"
echo -e "${GREEN}==================================================================${NC}"
exit 0
