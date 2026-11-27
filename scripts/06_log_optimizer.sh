#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD MODULE: [06] Enterprise Log Rotation & Disk Space Optimizer
# Version:          1.9.1 (Security Audit Hardened: 3-Tier Sync with Root
#                   /var/log/php-fpm Slowlog, Base-10 Octal-Safe Arithmetic,
#                   Safe Non-Destructive Default Vacuum, Legacy v1.8 Fallback)
# Architecture:     Multi-Layer Log Rotation | Journal Vacuum | Zero-Crash SRE
# Platform:         Debian 11/12/13, Ubuntu 22.04/24.04/26.04 LTS
# ==============================================================================
set -euo pipefail

ESC=$(printf '\033')
B_O=$(printf '\133')
B_C=$(printf '\135')

# ------------------------------------------------------------------------------
# 1. TERMINAL THEME & ABSOLUTE CURSOR POSITIONING
# ------------------------------------------------------------------------------
if tput setaf 1 >/dev/null 2>&1; then
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

if tput hpa 47 >/dev/null 2>&1; then
    COL_MID=$(tput hpa 47)
else
    COL_MID="${ESC}${B_O}48G"
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ [FATAL] This module must be executed as root.${NC}" >&2
    exit 1
fi

if ! command -v logrotate >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get -o DPkg::Lock::Timeout=60 update -qq && apt-get -o DPkg::Lock::Timeout=60 install -y -qq logrotate || true
fi

# ------------------------------------------------------------------------------
# 2. CONFIGURATION DEFAULTS & SWITCHES
# ------------------------------------------------------------------------------
OPTIMIZE_VHOSTS=1
OPTIMIZE_SYSTEMD=1
VACUUM_IMMEDIATE=0         # Off by default so policy sync does not burn a rotation cycle
ROTATE_FREQUENCY="daily"   # daily / weekly
LOG_RETENTION=14           # Retention cycles
JOURNAL_CAP_MB=150         # Hard ceiling limit for systemd-journald (MB)

toggle_status() {
    local val="$1"
    if [ "$val" -eq 1 ]; then
        echo -e "${GREEN}[✔] ENABLED ${NC}"
    else
        echo -e "${GRAY}[ ] DISABLED${NC}"
    fi
}

# ------------------------------------------------------------------------------
# 3. LIVE STORAGE FOOTPRINT TELEMETRY
# ------------------------------------------------------------------------------
get_size() {
    local path="$1"
    if [ -d "$path" ]; then
        du -sh "$path" 2>/dev/null | awk '{print $1}' || echo "0B"
    else
        echo "N/A"
    fi
}

get_journal_size() {
    if command -v journalctl >/dev/null 2>&1; then
        local j_out
        j_out=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?[BKMGT]' | head -n1 || true)
        echo "${j_out:-0B}"
    else
        echo "N/A"
    fi
}

get_vhosts_log_size() {
    if [ -d "/var/www" ]; then
        shopt -s nullglob
        local log_dirs=( /var/www/*/logs )
        shopt -u nullglob

        if [ ${#log_dirs[@]} -gt 0 ]; then
            du -ch "${log_dirs[@]}" 2>/dev/null | awk '/total$/ {print $1}' || echo "0B"
        else
            echo "0B"
        fi
    else
        echo "0B"
    fi
}

# ------------------------------------------------------------------------------
# 4. TUI DASHBOARD RENDERER
# ------------------------------------------------------------------------------
draw_log_tui() {
    clear
    local sz_var_log sz_vhost sz_journal
    sz_var_log=$(get_size "/var/log")
    sz_vhost=$(get_vhosts_log_size)
    sz_journal=$(get_journal_size)

    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Module: %-25s${NC}\n" "BASHBOARD LOG OPTIMIZER (V1.9.1)" "Storage & Retention TUI"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   📋 ${PURPLE}${BOLD}STORAGE FOOTPRINT TELEMETRY (LIVE)${NC}"
    echo -e "      System Log Footprint: ${YELLOW}$sz_var_log${NC}  │  VHost Sites Log: ${YELLOW}$sz_vhost${NC}  │  Journal: ${YELLOW}$sz_journal${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    printf "   ${CYAN}[1]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Target: ${WHITE}/etc/logrotate.d/vhost-*${NC}\n" "$(toggle_status "$OPTIMIZE_VHOSTS")" "Synchronize VHost Policies"
    printf "   ${CYAN}[2]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Target: ${WHITE}/etc/systemd/journald.conf.d/${NC}\n" "$(toggle_status "$OPTIMIZE_SYSTEMD")" "Cap Journald Storage"
    printf "   ${CYAN}[3]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Action: ${WHITE}Force rotate & vacuum now${NC}\n" "$(toggle_status "$VACUUM_IMMEDIATE")" "Force Rotate & Vacuum"

    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ⚙️  ${PURPLE}${BOLD}RETENTION POLICY & COMPRESSION CONFIGURATION${NC}"
    printf "      %-22s: ${YELLOW}%-22s${NC}${COL_MID}${GRAY}│${NC} Toggle Policy: ${CYAN}[4]${NC}\n" "Rotate Frequency" "$ROTATE_FREQUENCY"
    printf "      %-22s: ${YELLOW}%-22s${NC}${COL_MID}${GRAY}│${NC} Change with  : ${CYAN}[5]${NC}\n" "Log File Retention" "${LOG_RETENTION} cycles"
    printf "      %-22s: ${YELLOW}%-22s${NC}${COL_MID}${GRAY}│${NC} Change with  : ${CYAN}[6]${NC}\n" "Max Journald Limit" "${JOURNAL_CAP_MB} MB"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    echo -e "   ${GREEN}${BOLD}[9] ⚡ ENFORCE LOGROTATION & RECLAIM DISK${NC}"
    echo -e "   ${RED}${BOLD}[0] ↩️  CANCEL AND RETURN TO BASHBOARD${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# ------------------------------------------------------------------------------
# 5. INTERACTIVE MENU EVENT LOOP
# ------------------------------------------------------------------------------
while true; do
    draw_log_tui
    tput cnorm 2>/dev/null || true
    echo -ne "\n   ${BOLD}${WHITE}Toggle or Modify Parameters [0-9]:${NC} "
    read -r opt || opt="0"

    case "$opt" in
        1) OPTIMIZE_VHOSTS=$(( 1 - OPTIMIZE_VHOSTS )) ;;
        2) OPTIMIZE_SYSTEMD=$(( 1 - OPTIMIZE_SYSTEMD )) ;;
        3) VACUUM_IMMEDIATE=$(( 1 - VACUUM_IMMEDIATE )) ;;
        4)
            if [ "$ROTATE_FREQUENCY" == "daily" ]; then
                ROTATE_FREQUENCY="weekly"
            else
                ROTATE_FREQUENCY="daily"
            fi
            ;;
        5)
            echo ""
            read -rp "   Enter log retention cycle count (e.g., 7, 14, 30): " user_ret
            # Force base-10 interpretation to eliminate octal crash on leading zeros (e.g., 08, 09)
            if [[ "$user_ret" =~ ^[0-9]+$ ]] && [ "$((10#$user_ret))" -ge 1 ]; then
                LOG_RETENTION=$((10#$user_ret))
            else
                echo -e "   ${RED}Invalid number. Keeping ${LOG_RETENTION}.${NC}"
                sleep 1
            fi
            ;;
        6)
            echo ""
            read -rp "   Enter Max Systemd Journal limit in MB (e.g., 100, 150, 300): " user_cap
            if [[ "$user_cap" =~ ^[0-9]+$ ]] && [ "$((10#$user_cap))" -ge 10 ]; then
                JOURNAL_CAP_MB=$((10#$user_cap))
            else
                echo -e "   ${RED}Invalid size. Keeping ${JOURNAL_CAP_MB}MB.${NC}"
                sleep 1
            fi
            ;;
        9)
            if [ "$OPTIMIZE_VHOSTS" -eq 0 ] && [ "$OPTIMIZE_SYSTEMD" -eq 0 ] && [ "$VACUUM_IMMEDIATE" -eq 0 ]; then
                echo -e "\n   ${YELLOW}No optimizations selected! Please enable at least one action.${NC}"
                sleep 1.5
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

# ==============================================================================
# 6. EXECUTION PHASE: LOG RETENTION ORCHESTRATION
# ==============================================================================
clear
echo -e "${CYAN}==================================================================${NC}"
echo -e "   🚀 ${BOLD}${WHITE}Applying Enterprise Log Retention & Disk Reclamation...${NC}"
echo -e "${CYAN}==================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 6.1 MULTI-TENANT 3-TIER DEDICATED LOGROTATE SYNCHRONIZATION
# ------------------------------------------------------------------------------
if [ "$OPTIMIZE_VHOSTS" -eq 1 ]; then
    echo -e "${BLUE}--- [1/3] Synchronizing Tenant-Dedicated Logrotate Drop-ins ---${NC}"

    rm -f "/etc/logrotate.d/bashboard-vhosts"

    if [ -d "/var/log/php-fpm" ] && [ ! -L "/var/log/php-fpm" ]; then
        chown root:root /var/log/php-fpm
        chmod 750 /var/log/php-fpm
    fi

    # 1. Purge orphaned logrotate drop-ins for manually deleted sites
    shopt -s nullglob
    existing_dropins=( /etc/logrotate.d/vhost-* )
    shopt -u nullglob
    for dropin in "${existing_dropins[@]}"; do
        d_name=$(basename "$dropin" | sed 's/^vhost-//')
        if [ ! -d "/var/www/$d_name/logs" ]; then
            rm -f "$dropin"
            echo -e "   ${YELLOW}🗑️  Purged orphaned logrotate drop-in:${NC} $dropin"
        fi
    done

    # 2. Synchronize active virtual host logrotate policies
    shopt -s nullglob
    domains=( /var/www/* )
    shopt -u nullglob

    for d in "${domains[@]}"; do
        domain_name=$(basename "$d")
        [[ "$domain_name" == "html" || "$domain_name" == "_acme-challenge" ]] && continue

        if [ -d "$d/logs" ] && [ ! -L "$d/logs" ]; then
            vhost_user=""
            slowlog_path=""
            state_f="/etc/bashboard/sites/${domain_name}.state"

            if [ -f "$state_f" ] && [ ! -L "$state_f" ]; then
                vhost_user=$(grep -E "^TENANT_USER=" "$state_f" 2>/dev/null | cut -d'=' -f2- || true)
                slowlog_path=$(grep -E "^SLOWLOG_FILE=" "$state_f" 2>/dev/null | cut -d'=' -f2- || true)
            elif [ -f "$d/.bashboard-state" ] && [ ! -L "$d/.bashboard-state" ] && [ "$(stat -c '%u' "$d/.bashboard-state" 2>/dev/null)" = "0" ]; then
                vhost_user=$(grep -E "^TENANT_USER=" "$d/.bashboard-state" 2>/dev/null | cut -d'=' -f2- || true)
            fi

            if [[ -z "$vhost_user" ]] || ! id -u "$vhost_user" >/dev/null 2>&1; then
                vhost_user=$(stat -c '%U' "$d/public_html" 2>/dev/null || echo "www-data")
            fi
            if ! id -u "$vhost_user" >/dev/null 2>&1 || [[ ! "$vhost_user" =~ ^v_[a-z0-9_]+$ ]]; then
                vhost_user="www-data"
            else
                usermod -a -G "$vhost_user" www-data 2>/dev/null || true
                chown -h "root:$vhost_user" "$d" 2>/dev/null || true
                chmod 750 "$d" 2>/dev/null || true
            fi

            logs_dir="$d/logs"
            php_logs_dir="$logs_dir/php"

            # Tier 1: Nginx log directory remains non-writable by tenant (CVE-2016-1247 safe)
            chown -h "www-data:$vhost_user" "$logs_dir" 2>/dev/null || true
            chmod 750 "$logs_dir" 2>/dev/null || true

            shopt -s nullglob
            for nlog in "$logs_dir"/nginx_*.log "$logs_dir"/uploads_*.log; do
                if [ -f "$nlog" ] && [ ! -L "$nlog" ]; then
                    chown -h "www-data:$vhost_user" "$nlog" 2>/dev/null || true
                    chmod 640 "$nlog" 2>/dev/null || true
                fi
            done

            # Tier 2: Split logs/php/ hierarchy (v1.9+) vs flat legacy logs/php_*.log (v1.8)
            php_log_glob=""
            php_su_line=""
            if [ -d "$php_logs_dir" ] && [ ! -L "$php_logs_dir" ]; then
                chown -h "$vhost_user:$vhost_user" "$php_logs_dir" 2>/dev/null || true
                chmod 750 "$php_logs_dir" 2>/dev/null || true
                for plog in "$php_logs_dir"/php_*.log; do
                    if [ -f "$plog" ] && [ ! -L "$plog" ]; then
                        chown -h "$vhost_user:$vhost_user" "$plog" 2>/dev/null || true
                        chmod 640 "$plog" 2>/dev/null || true
                    fi
                done
                php_log_glob="$php_logs_dir/php_*.log"
                php_su_line="su $vhost_user $vhost_user"
            else
                for plog in "$logs_dir"/php_*.log; do
                    if [ -f "$plog" ] && [ ! -L "$plog" ]; then
                        chown -h "$vhost_user:$vhost_user" "$plog" 2>/dev/null || true
                        chmod 660 "$plog" 2>/dev/null || true
                    fi
                done
                php_log_glob="$logs_dir/php_*.log"
                php_su_line="su www-data $vhost_user"
            fi
            shopt -u nullglob

            cat > "/etc/logrotate.d/vhost-$domain_name" <<EOF
# Bashboard Dedicated Logrotate Policy for $domain_name (CVE-2016-1247 & Symlink Safe)
$logs_dir/nginx_*.log $logs_dir/uploads_*.log {
    su www-data $vhost_user
    ${ROTATE_FREQUENCY}
    missingok
    rotate ${LOG_RETENTION}
    compress
    delaycompress
    notifempty
    create 0640 www-data $vhost_user
    sharedscripts
    postrotate
        if systemctl is-active --quiet nginx.service 2>/dev/null; then
            systemctl kill -s USR1 nginx.service 2>/dev/null || true
        elif [ -s /run/nginx.pid ]; then
            kill -USR1 \$(cat /run/nginx.pid) 2>/dev/null || true
        fi
    endscript
}

$php_log_glob {
    ${php_su_line}
    ${ROTATE_FREQUENCY}
    missingok
    rotate ${LOG_RETENTION}
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

            # Tier 3: Root-isolated FPM master slowlog (/var/log/php-fpm/<pool>_slow.log)
            if [[ "$slowlog_path" == /var/log/php-fpm/* ]] && [ ! -L "$slowlog_path" ]; then
                if [ -f "$slowlog_path" ]; then
                    chown -h root:root "$slowlog_path" 2>/dev/null || true
                    chmod 640 "$slowlog_path" 2>/dev/null || true
                fi
                cat >> "/etc/logrotate.d/vhost-$domain_name" <<EOF

$slowlog_path {
    su root root
    ${ROTATE_FREQUENCY}
    missingok
    rotate ${LOG_RETENTION}
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
            fi

            echo -e "   ${GREEN}✅ Synced drop-in:${NC} /etc/logrotate.d/vhost-$domain_name (Tenant: $vhost_user)"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 6.2 SYSTEMD JOURNAL HARD LIMITS
# ------------------------------------------------------------------------------
if [ "$OPTIMIZE_SYSTEMD" -eq 1 ]; then
    echo -e "\n${BLUE}--- [2/3] Hardening Systemd Journald Storage Caps ---${NC}"
    mkdir -p "/etc/systemd/journald.conf.d"
    JOURNAL_CONF="/etc/systemd/journald.conf.d/99-bashboard-limits.conf"

    cat > "$JOURNAL_CONF" <<EOF
[Journal]
SystemMaxUse=${JOURNAL_CAP_MB}M
SystemKeepFree=1G
SystemMaxFileSize=20M
MaxRetentionSec=1month
EOF

    systemctl reload-or-restart systemd-journald 2>/dev/null || systemctl restart systemd-journald 2>/dev/null || true
    echo -e "   ${GREEN}✅ Configured: ${CYAN}$JOURNAL_CONF${NC} (Hard Ceiling: ${JOURNAL_CAP_MB}MB)"
fi

# ------------------------------------------------------------------------------
# 6.3 IMMEDIATE FORCE-ROTATE & VACUUM (OPT-IN)
# ------------------------------------------------------------------------------
if [ "$VACUUM_IMMEDIATE" -eq 1 ]; then
    echo -e "\n${BLUE}--- [3/3] Performing Immediate Disk Space Reclamation ---${NC}"

    if command -v journalctl >/dev/null 2>&1; then
        echo -e "   ${GRAY}Vacuuming systemd-journal logs down to ${JOURNAL_CAP_MB}MB...${NC}"
        journalctl --vacuum-size="${JOURNAL_CAP_MB}M" >/dev/null 2>&1 || true
    fi

    shopt -s nullglob
    vhost_rotates=( /etc/logrotate.d/vhost-* )
    shopt -u nullglob

    for vr in "${vhost_rotates[@]}"; do
        rot_err=""
        if ! rot_err=$(logrotate -f "$vr" 2>&1); then
            echo -e "   ${YELLOW}⚠️  Rotation warning for $(basename "$vr"):${NC} ${rot_err}"
        fi
    done

    retention_days=$((10#$LOG_RETENTION))
    if [ "$ROTATE_FREQUENCY" == "weekly" ]; then
        retention_days=$(( 10#$LOG_RETENTION * 7 ))
    fi

    echo -e "   ${GRAY}Purging dead-weight archives older than ${retention_days} days...${NC}"
    find /var/log/nginx -maxdepth 2 -type f -name "*.gz" -mtime +"${retention_days}" -delete 2>/dev/null || true
    find /var/log/php-fpm -maxdepth 2 -type f -name "*.gz" -mtime +"${retention_days}" -delete 2>/dev/null || true
    find /var/www/*/logs -maxdepth 2 -type f -name "*.gz" -mtime +"${retention_days}" -delete 2>/dev/null || true

    echo -e "   ${GREEN}✅ Immediate vacuum complete. Inactive logs reclaimed.${NC}"
fi

# ------------------------------------------------------------------------------
# 7. LOGROTATE SYNTAX ASSERTION & VERIFICATION
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}Validating logrotate configuration syntax...${NC}"
logrotate_audit=$(logrotate -d /etc/logrotate.conf 2>&1 || true)
if echo "$logrotate_audit" | grep -qiE "(^| )error:|failed"; then
    echo -e "   ${RED}❌ Logrotate validation encountered syntax errors:${NC}"
    echo "$logrotate_audit" | grep -iE "(^| )error:|failed" | sed 's/^/      /'
else
    echo -e "   ${GREEN}✅ All Logrotate configurations verified clean and syntax-safe.${NC}"
fi

# ------------------------------------------------------------------------------
# 8. FINAL STATUS REPORT
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}=================================================================="
echo -e "   🎉 STORAGE FOOTPRINT & LOG ROTATION OPTIMIZED"
echo -e "==================================================================${NC}"
printf "   %-26s: %b\n" "Current /var/log Size" "${YELLOW}$(get_size "/var/log")${NC}"
printf "   %-26s: %b\n" "Current VHost Log Size" "${YELLOW}$(get_vhosts_log_size)${NC}"
printf "   %-26s: %b\n" "Current Journal Size" "${YELLOW}$(get_journal_size)${NC}"
echo -e "   --------------------------------------------------------------"
echo -e "   Policy: Retain ${YELLOW}${LOG_RETENTION} ${ROTATE_FREQUENCY}${NC} compressed log cycles."
echo -e "   Journal Hard Cap: ${YELLOW}${JOURNAL_CAP_MB} MB${NC}"
echo -e "${GREEN}==================================================================${NC}"
exit 0
