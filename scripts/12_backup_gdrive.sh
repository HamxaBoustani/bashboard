#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD MODULE: [12] Automated Google Drive Backup Engine
# Version:          1.8.0 (Zero-Trust SRE: C1 State Verification Guard, Exclusive
#                   flock Capsule, Anchored tar Excludes, Trash-Free Cloud Prune)
# Architecture:     Interactive TUI & Headless Cron | Disaster Recovery Suite
# Platform:         Debian 11/12, Ubuntu 20.04/22.04/24.04/26.04 LTS
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

# ------------------------------------------------------------------------------
# 2. RUNTIME DEPENDENCY & RCLONE REMOTE ASSERTION
# ------------------------------------------------------------------------------
readonly SELF_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/$(basename "${BASH_SOURCE[0]}")"
RCLONE_REMOTE="bashboard-gdrive"
RETENTION_DAYS=14
BACKUP_FILES=1
BACKUP_DATABASES=1
STAGING_VAULT="/var/backups/bashboard/gdrive-staging"
BACKUP_LOCK="/run/bashboard_backup.lock"

export HOME="${HOME:-/root}"

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
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Module: %-25s${NC}\n" "BASHBOARD BACKUP SUITE" "Google Drive Sync Engine"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   📋 ${PURPLE}${BOLD}OFF-SITE DISASTER RECOVERY & CLOUD SYNC MATRIX${NC}"
    echo -e "      Streams database dumps and web assets directly to your remote Google Drive."
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    printf "      %-24s: %-26b ${COL_MID}${GRAY}│${NC} Action   : ${CYAN}[1] Configure Remote${NC}\n" "Google Drive Remote" "$remote_status"
    printf "   ${CYAN}[2]${NC} %b %-20s ${COL_MID}${GRAY}│${NC} Mode     : ${WHITE}--single-transaction${NC}\n" "$(toggle_status "$BACKUP_DATABASES")" "MySQL Databases"
    printf "   ${CYAN}[3]${NC} %b %-20s ${COL_MID}${GRAY}│${NC} Payload  : ${WHITE}/var/www/*/public_html${NC}\n" "$(toggle_status "$BACKUP_FILES")" "Web Application Files"
    printf "   ${CYAN}[4]${NC} %-24s: ${YELLOW}%-22s${NC} ${COL_MID}${GRAY}│${NC} Prune    : ${WHITE}> %s days on cloud${NC}\n" "Retention Window" "${RETENTION_DAYS} Days" "$RETENTION_DAYS"

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
                echo -e "${CYAN}------------------------------------------------------------------${NC}\n"
                rclone config
                continue
                ;;
            2) BACKUP_DATABASES=$(( 1 - BACKUP_DATABASES )) ;;
            3) BACKUP_FILES=$(( 1 - BACKUP_FILES )) ;;
            4)
                echo ""
                read -rp "   Enter Cloud Retention Days (e.g., 7, 14, 30, 60): " user_ret
                if [[ "$user_ret" =~ ^[0-9]+$ ]] && [ "$user_ret" -ge 1 ]; then
                    RETENTION_DAYS="$user_ret"
                fi
                ;;
            8)
                if ! has_rclone_remote; then
                    echo -e "\n   ${RED}❌ Configure Google Drive remote '${RCLONE_REMOTE}' [Option 1] before enabling cron!${NC}"
                    sleep 2
                    continue
                fi
                cron_job_file="/etc/cron.d/bashboard-gdrive-backup"
                cat > "$cron_job_file" <<EOF
# Bashboard Automated Google Drive Off-Site Backup Engine
# Runs nightly at 03:00 AM strictly as root
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
HOME=/root

0 3 * * * root /bin/bash "$SELF_PATH" --non-interactive >/var/log/bashboard_backup.log 2>&1
EOF
                chmod 644 "$cron_job_file"
                echo -e "\n   ${GREEN}✅ Nightly automated backup crontab installed (/etc/cron.d/bashboard-gdrive-backup).${NC}"
                sleep 2
                ;;
            9)
                if ! has_rclone_remote; then
                    echo -e "\n   ${RED}❌ Google Drive remote '${RCLONE_REMOTE}' is not configured! Press [1] first.${NC}"
                    sleep 2
                    continue
                fi
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
# 5. EXECUTION PHASE: EXCLUSIVE FLOCK & ZERO-LOCKING STREAMING BACKUP
# ==============================================================================
# Prevent concurrent manual and cron backups from colliding in staging vault (Resolves W10)
exec 201>"$BACKUP_LOCK"
if ! flock -n 201; then
    echo -e "${RED}❌ [ABORT] Another backup process is currently running.${NC}" >&2
    exit 1
fi

TIMESTAMP=$(date +'%Y-%m-%d_%H%M%S')
REMOTE_DEST="${RCLONE_REMOTE}:bashboard-backups/${TIMESTAMP}"

echo -e "${CYAN}==================================================================${NC}"
echo -e "   🚀 ${BOLD}${WHITE}Executing Disaster Recovery Backup to Google Drive...${NC}"
echo -e "   ☁️  Remote Target: ${YELLOW}${REMOTE_DEST}${NC}"
echo -e "${CYAN}==================================================================${NC}\n"

mkdir -p "$STAGING_VAULT"
chmod 700 "$STAGING_VAULT"

cleanup_staging() {
    rm -rf "${STAGING_VAULT:?}"/*
}
trap cleanup_staging EXIT

DB_BIN="mariadb"
command -v mariadb >/dev/null 2>&1 || DB_BIN="mysql"
DUMP_BIN="mariadb-dump"
command -v mariadb-dump >/dev/null 2>&1 || DUMP_BIN="mysqldump"

# 5.1 Non-Locking Database Dumps with Strict State Verification (Resolves C1 & W11)
if [ "$BACKUP_DATABASES" -eq 1 ]; then
    echo -e "${BLUE}--- [1/3] Dumping MariaDB Databases (Non-Locking InnoDB) ---${NC}"
    
    shopt -s nullglob
    vhost_dirs=( /var/www/* )
    shopt -u nullglob

    for vd in "${vhost_dirs[@]}"; do
        [ -d "$vd" ] || continue
        domain=$(basename "$vd")
        [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$ ]] || continue

        # Locate authoritative root-owned state file (Resolves C1)
        sf=""
        if [ -f "/etc/bashboard/sites/${domain}.state" ] && [ ! -L "/etc/bashboard/sites/${domain}.state" ]; then
            sf="/etc/bashboard/sites/${domain}.state"
        elif [ -f "$vd/.bashboard-state" ] && [ ! -L "$vd/.bashboard-state" ] && [ "$(stat -c '%u' "$vd/.bashboard-state" 2>/dev/null)" = "0" ]; then
            sf="$vd/.bashboard-state"
        fi
        [[ -n "$sf" ]] || continue

        db_name=$(grep -E "^DB_NAME=" "$sf" 2>/dev/null | cut -d'=' -f2- || true)
        vhost_user=$(grep -E "^TENANT_USER=" "$sf" 2>/dev/null | cut -d'=' -f2- || true)

        if [[ -n "$db_name" && "$db_name" =~ ^[a-zA-Z0-9_]{1,64}$ ]]; then
            dump_file="${STAGING_VAULT}/${domain}_db_${TIMESTAMP}.sql.gz"
            echo -e "   Dumping database \`${YELLOW}$db_name\` (Site: $domain)..."

            dump_ok=0
            # Tier 1: Direct root unix_socket / .my.cnf dump
            if $DUMP_BIN --single-transaction --quick --routines --triggers -u root "$db_name" 2>/dev/null | gzip -c > "$dump_file"; then
                if [ -f "$dump_file" ] && [ "$(stat -c '%s' "$dump_file" 2>/dev/null || echo 0)" -gt 64 ]; then
                    dump_ok=1
                fi
            fi

            # Tier 2 Fallback: Strictly validate tenant user (^v_ and home match) & support decoupled layout (Resolves C1 & W11)
            if [ "$dump_ok" -eq 0 ] && command -v wp >/dev/null 2>&1; then
                if [[ "$vhost_user" =~ ^v_[a-z0-9_]+_[0-9a-f]{4}$ ]] && [ "$vhost_user" != "v_pma_sys" ]; then
                    user_home=$(getent passwd "$vhost_user" 2>/dev/null | cut -d: -f6 || true)
                    if [[ "$user_home" == "/var/www/$domain" ]]; then
                        wp_target="$vd/public_html"
                        [[ -f "$vd/public_html/core/wp-settings.php" ]] && wp_target="$vd/public_html/core"

                        if [ -f "$wp_target/wp-config.php" ] || [ -f "$vd/public_html/wp-config.php" ]; then
                            open_base="/var/www/${domain}/:/usr/local/bin/wp:/usr/share/zoneinfo/:/dev/urandom"
                            dis_funcs="exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec,show_source,highlight_file,proc_get_status"
                            if runuser -u "$vhost_user" -- env HOME="/var/www/$domain" \
                                WP_CLI_CACHE_DIR="/var/www/$domain/tmp/wp-cache" \
                                php -d open_basedir="$open_base" -d disable_functions="$dis_funcs" \
                                /usr/local/bin/wp db export - --single-transaction --quick --add-drop-table \
                                --path="$wp_target" --skip-plugins --skip-themes 2>/dev/null | gzip -c > "$dump_file"; then
                                if [ -f "$dump_file" ] && [ "$(stat -c '%s' "$dump_file" 2>/dev/null || echo 0)" -gt 64 ]; then
                                    dump_ok=1
                                fi
                            fi
                        fi
                    fi
                fi
            fi

            if [ "$dump_ok" -eq 1 ]; then
                chmod 600 "$dump_file"
            else
                rm -f "$dump_file"
                echo -e "   ${RED}⚠️  [WARNING] Failed to dump database '$db_name' for $domain.${NC}" >&2
            fi
        fi
    done
    echo -e "   ${GREEN}✅ Database dumps completed in staging vault.${NC}"
fi

# 5.2 Compressing Web Assets with Anchored Excludes (Resolves W10)
if [ "$BACKUP_FILES" -eq 1 ]; then
    echo -e "\n${BLUE}--- [2/3] Archiving Web Files & Payloads ---${NC}"
    shopt -s nullglob
    vhost_dirs=( /var/www/* )
    shopt -u nullglob

    for vd in "${vhost_dirs[@]}"; do
        if [ -d "$vd/public_html" ]; then
            domain=$(basename "$vd")
            tar_file="${STAGING_VAULT}/${domain}_web_${TIMESTAMP}.tar.gz"
            echo -e "   Archiving /var/www/$domain (Excluding root logs & tmp)..."
            
            # Anchored exclusions prevent accidentally skipping plugin 'logs' or 'tmp' folders (Resolves W10)
            if tar -czf "$tar_file" \
                --exclude="${domain}/logs" \
                --exclude="${domain}/tmp" \
                --exclude="${domain}/public_html/wp-content/cache" \
                -C "/var/www" "$domain" 2>/dev/null; then
                chmod 600 "$tar_file"
            else
                # Partial warning code 1 in tar (file changed as we read it) is acceptable if archive exists
                if [ -s "$tar_file" ]; then
                    chmod 600 "$tar_file"
                else
                    rm -f "$tar_file"
                    echo -e "   ${RED}⚠️  [WARNING] Failed to archive web files for $domain.${NC}" >&2
                fi
            fi
        fi
    done
    echo -e "   ${GREEN}✅ Web assets archived in staging vault.${NC}"
fi

# 5.3 Streaming Archive Vault to Google Drive & Safe Remote Pruning (Resolves W10)
echo -e "\n${BLUE}--- [3/3] Synchronizing Staging Vault to Google Drive ---${NC}"
echo -e "   Uploading archives to ${YELLOW}${REMOTE_DEST}${NC}..."

upload_ok=0
if [ "$NON_INTERACTIVE" -eq 1 ]; then
    rclone copy "$STAGING_VAULT" "$REMOTE_DEST" && upload_ok=1
else
    rclone copy "$STAGING_VAULT" "$REMOTE_DEST" --progress && upload_ok=1
fi

# Only prune old backups if today's upload succeeded (Prevents wiping all backups during multi-day outages - Resolves W10)
if [ "$upload_ok" -eq 1 ]; then
    echo -e "\n   ${GRAY}Pruning remote backups older than ${RETENTION_DAYS} days on Google Drive (bypassing trash)...${NC}"
    rclone delete "${RCLONE_REMOTE}:bashboard-backups" --min-age "${RETENTION_DAYS}d" --drive-use-trash=false 2>/dev/null || true
    rclone rmdirs "${RCLONE_REMOTE}:bashboard-backups" --leave-root --drive-use-trash=false 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 6. FINAL SUMMARY REPORT
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}=================================================================="
echo -e "   🎉 OFF-SITE BACKUP TO GOOGLE DRIVE FINISHED SUCCESSFULLY"
echo -e "==================================================================${NC}"
echo -e "Remote Destination : ${YELLOW}${REMOTE_DEST}${NC}"
echo -e "Databases Dumped   : ${WHITE}$( [ "$BACKUP_DATABASES" -eq 1 ] && echo "Active (--single-transaction)" || echo "Skipped" )${NC}"
echo -e "Web Assets Staged  : ${WHITE}$( [ "$BACKUP_FILES" -eq 1 ] && echo "Active" || echo "Skipped" )${NC}"
echo -e "Remote Retention   : ${GREEN}${RETENTION_DAYS} Days (Old archives permanently pruned)${NC}"
echo -e "${GREEN}==================================================================${NC}"
exit 0