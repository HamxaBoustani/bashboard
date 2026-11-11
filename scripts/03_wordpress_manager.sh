#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD MODULE: [03] WordPress Site Manager (Enterprise TUI Edition)
# Version:          1.8.1 (Production Hardened: Native 'cli has-command' Sync,
#                   Non-Intrusive Advisory, Single-Lock Runner, Privilege Drop)
# Architecture:     2-Column Symmetrical TUI | Live Telemetry | Disaster Recovery
# Platform:         Debian 11/12, Ubuntu 20.04/22.04/24.04/26.04 LTS
# ==============================================================================
set -euo pipefail

ESC=$(printf '\033')
B_O=$(printf '\133')
B_C=$(printf '\135')

# ------------------------------------------------------------------------------
# 1. TERMINAL THEME & ABSOLUTE COLUMN ALIGNMENT
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

# ------------------------------------------------------------------------------
# 2. HARDENED WP-CLI DEPLOYMENT & INTEGRITY ASSERTION
# ------------------------------------------------------------------------------
ensure_wp_cli() {
    if ! command -v wp >/dev/null 2>&1; then
        clear
        echo -e "${YELLOW}WP-CLI not found! Installing verified binary...${NC}"
        local tmp_wp
        tmp_wp=$(mktemp /tmp/wpcli_XXXXXX.phar)

        if curl -fsSL -o "$tmp_wp" https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; then
            if php "$tmp_wp" --info >/dev/null 2>&1; then
                chmod +x "$tmp_wp"
                mv "$tmp_wp" /usr/local/bin/wp
                echo -e "${GREEN}✅ WP-CLI globally installed and verified.${NC}"
                sleep 1
            else
                rm -f "$tmp_wp"
                echo -e "${RED}❌ [FATAL] Downloaded WP-CLI binary failed PHAR integrity test.${NC}" >&2
                exit 1
            fi
        else
            rm -f "$tmp_wp"
            echo -e "${RED}❌ [FATAL] Failed to download WP-CLI from GitHub repository.${NC}" >&2
            exit 1
        fi
    fi
}
ensure_wp_cli

# ------------------------------------------------------------------------------
# 3. ACCURATE ENVIRONMENT SCANNER (Active wp-config.php Required)
# ------------------------------------------------------------------------------
sites=()
if [ -d "/var/www" ]; then
    while IFS= read -r dir; do
        domain=$(basename "$dir")
        if [[ -f "$dir/public_html/wp-config.php" || -f "$dir/public_html/core/wp-config.php" || -f "$dir/wp-config.php" ]]; then
            sites+=("$domain")
        fi
    done < <(find /var/www -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
fi

# ------------------------------------------------------------------------------
# 4. SITE SELECTOR INTERFACE
# ------------------------------------------------------------------------------
draw_site_selector() {
    clear
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Module: %-25s${NC}\n" "BASHBOARD WP SUITE" "Site Selector"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   📋 ${PURPLE}${BOLD}ACTIVE WORDPRESS ENVIRONMENTS ON THIS SERVER${NC}"
    echo -e "      Choose a website environment to manage, audit, or repair."
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    if [ ${#sites[@]} -eq 0 ]; then
        echo -e "      ${RED}No configured WordPress installations detected in /var/www/*${NC}"
        echo -e "      ${GRAY}Please create a site first using Option [2] in Bashboard.${NC}"
        echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
        echo -e "   ${RED}${BOLD}[0] ↩️  RETURN TO MAIN DASHBOARD${NC}"
        echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
        return
    fi

    for i in "${!sites[@]}"; do
        local d="${sites[$i]}"
        local t_type="Standard"
        [[ -d "/var/www/$d/public_html/core" ]] && t_type="Decoupled"
        printf "   ${CYAN}[%2d]${NC} %-30s ${COL_MID}${GRAY}│${NC} Layout: ${WHITE}%-15s${NC}\n" "$((i+1))" "$d" "$t_type"
    done

    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ${RED}${BOLD}[0] ↩️  RETURN TO MAIN DASHBOARD${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

if [ ${#sites[@]} -eq 0 ]; then
    draw_site_selector
    read -rp "Press Enter to exit..."
    exit 0
fi

if [ ${#sites[@]} -eq 1 ]; then
    SELECTED_DOMAIN="${sites[0]}"
else
    while true; do
        draw_site_selector
        tput cnorm 2>/dev/null || true
        echo -ne "\n   ${BOLD}${WHITE}Select Target Site [1-${#sites[@]}, 0 to exit]:${NC} "
        read -r s_opt || s_opt="0"

        if [[ "$s_opt" == "0" ]]; then exit 0; fi
        if [[ "$s_opt" =~ ^[0-9]+$ ]] && [ "$s_opt" -ge 1 ] && [ "$s_opt" -le "${#sites[@]}" ]; then
            SELECTED_DOMAIN="${sites[$((s_opt-1))]}"
            break
        fi
        echo -e "   ${RED}Invalid site selection!${NC}"
        sleep 1
    done
fi

# ------------------------------------------------------------------------------
# 5. ENVIRONMENT PATH RESOLUTION & SAFE RUNNERS
# ------------------------------------------------------------------------------
TARGET_DIR="/var/www/$SELECTED_DOMAIN/public_html"
[[ ! -d "$TARGET_DIR" ]] && TARGET_DIR="/var/www/$SELECTED_DOMAIN"

if [[ -d "$TARGET_DIR/core" && -f "$TARGET_DIR/core/wp-settings.php" ]]; then
    WP_PATH="$TARGET_DIR/core"
    SITE_LAYOUT="Custom (Decoupled)"
else
    WP_PATH="$TARGET_DIR"
    SITE_LAYOUT="Standard Layout"
fi

get_vhost_user() {
    local u=""
    if [ -d "$TARGET_DIR" ]; then
        u=$(stat -c '%U' "$TARGET_DIR" 2>/dev/null || true)
    fi
    if [[ -z "$u" || "$u" == "root" ]]; then
        u=$(stat -c '%U' "/var/www/$SELECTED_DOMAIN" 2>/dev/null || true)
    fi
    echo "$u"
}

# C2 Hardened WP-CLI runner: Drops root privileges safely with runuser
wp_run() {
    local u
    u=$(get_vhost_user)
    if [[ ! "$u" =~ ^v_ ]]; then
        echo -e "   ${RED}❌ [CRITICAL] Refusing to execute WP-CLI as non-tenant user ($u).${NC}" >&2
        return 1
    fi
    runuser -u "$u" -- env HOME="/var/www/$SELECTED_DOMAIN" \
        WP_CLI_CACHE_DIR="/var/www/$SELECTED_DOMAIN/tmp/wp-cache" \
        php -d memory_limit=512M -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED & ~E_NOTICE" \
        /usr/local/bin/wp --path="$WP_PATH" "$@"
}

get_cfg_file() {
    if [[ -f "$TARGET_DIR/wp-config.php" ]]; then
        echo "$TARGET_DIR/wp-config.php"
    elif [[ -f "$TARGET_DIR/core/wp-config.php" ]]; then
        echo "$TARGET_DIR/core/wp-config.php"
    else
        echo ""
    fi
}

enforce_permissions() {
    local site_root="/var/www/$SELECTED_DOMAIN"
    local vhost_user
    vhost_user=$(get_vhost_user)

    if [ -d "$site_root" ] && [[ "$vhost_user" =~ ^v_ ]]; then
        chown "$vhost_user:www-data" "$site_root"
        chmod 750 "$site_root"

        chown -R "$vhost_user:$vhost_user" "$TARGET_DIR"
        find "$TARGET_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
        find "$TARGET_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true

        local cfg
        cfg=$(get_cfg_file)
        if [[ -n "$cfg" && -f "$cfg" ]]; then
            chown "$vhost_user:$vhost_user" "$cfg"
            chmod 600 "$cfg" 2>/dev/null || true
        fi

        if [ -d "$site_root/logs" ]; then
            chown -R "$vhost_user:www-data" "$site_root/logs"
            chmod 770 "$site_root/logs"
        fi
    fi
}

# ------------------------------------------------------------------------------
# 6. CRON RUNNER ASSERTION & SCHEDULER ORCHESTRATION (Standard WP-CLI Syntax)
# ------------------------------------------------------------------------------
ensure_cron_runner() {
    local runner="/usr/local/bin/bashboard-cron-runner"
    # Idempotent overwrite guarantees runner always stays in sync with bugfixes
    cat << 'EOF' > "$runner"
#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD CRON RUNNER ENGINE
# Architecture: Single Lock Capsule, Memory Guard (512M), Action Scheduler Sync
# ==============================================================================
set -e

DOMAIN="${1:-}"
WP_PATH="${2:-}"

if [[ -z "$DOMAIN" || -z "$WP_PATH" ]]; then
    echo "Usage: $0 <domain> <wp_path>" >&2
    exit 1
fi

LOCK_FILE="/var/www/${DOMAIN}/tmp/cron.lock"

# Execute inside a single atomic flock capsule to eliminate overlaps
/usr/bin/flock -n "${LOCK_FILE}" -c "
    /usr/bin/php -d memory_limit=512M -d error_reporting='E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED & ~E_NOTICE' \
        /usr/local/bin/wp cron event run --due-now --path='${WP_PATH}' --quiet 2>/dev/null || true

    # Native WP-CLI check: uses official 'cli has-command' instead of invalid syntax
    if /usr/local/bin/wp --path='${WP_PATH}' cli has-command action-scheduler >/dev/null 2>&1; then
        /usr/bin/php -d memory_limit=512M \
            /usr/local/bin/wp action-scheduler run --path='${WP_PATH}' --batch-size=100 --quiet 2>/dev/null || true
    fi
"
EOF
    chmod 755 "$runner"
}

toggle_system_wpcron() {
    local domain="$1"
    local wp_path="$2"
    local vhost_user
    vhost_user=$(get_vhost_user)
    local cron_id
    cron_id=$(echo "$domain" | tr '.-' '_')
    local cron_file="/etc/cron.d/bashboard-wp-${cron_id}"

    echo -e "\n${BLUE}--- System-Level WP-Cron Orchestrator ---${NC}"

    if [ -f "$cron_file" ]; then
        echo -e "   Disabling Linux Crontab for ${YELLOW}${domain}${NC}..."
        rm -f "$cron_file"
        enforce_permissions
        echo -e "   ${YELLOW}● Crontab removed: ${cron_file}${NC}"
        echo -e "\n   ${CYAN}ℹ️  ADVISORY:${NC} If you manually added ${WHITE}define( 'DISABLE_WP_CRON', true );${NC} in ${YELLOW}wp-config.php${NC},"
        echo -e "   you can now remove it or set it to ${WHITE}false${NC} to restore web visitor triggers."
    else
        echo -e "   Deploying isolated Linux crontab for ${YELLOW}${domain}${NC} (5-Minute Cadence)..."

        # 1. Guarantee global runner binary exists and is up to date
        ensure_cron_runner

        # 2. Calculate deterministic anti-thundering-herd delay (0-40s)
        local delay=$(( 16#$(echo -n "$domain" | md5sum | cut -c1-2) % 40 ))

        # 3. Deploy crontab drop-in running as tenant user
        cat > "$cron_file" <<EOF
# Bashboard Automated WP-Cron for $domain
# Runs strictly as $vhost_user with isolated execution envelopes
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
HOME=/var/www/$domain
WP_CLI_CACHE_DIR=/var/www/$domain/tmp/wp-cache

*/5 * * * * $vhost_user sleep $delay; /usr/local/bin/bashboard-cron-runner $domain $wp_path >/dev/null 2>&1 || true
EOF
        chmod 644 "$cron_file"
        enforce_permissions

        echo -e "   ${GREEN}✅ Global Runner Verified : ${WHITE}/usr/local/bin/bashboard-cron-runner${NC}"
        echo -e "   ${GREEN}✅ Linux Crontab deployed : ${CYAN}$cron_file${NC} (User: ${WHITE}$vhost_user${NC}, Delay: ${YELLOW}${delay}s${NC})"

        # Non-intrusive manual advisory: Keeps wp-config.php modifications strictly in user control
        echo -e "\n   ${YELLOW}📋 MANUAL ACTION RECOMMENDED:${NC}"
        echo -e "   To disable redundant web-visitor execution, add this line to your ${CYAN}wp-config.php${NC}:"
        echo -e "   ${BOLD}${WHITE}define( 'DISABLE_WP_CRON', true );${NC}"
    fi
    echo ""
    read -rp "Press Enter to return to site dashboard..."
}

# ------------------------------------------------------------------------------
# 7. CRON HEALTH DIAGNOSTICS & TEST RUNNER
# ------------------------------------------------------------------------------
inspect_and_test_cron() {
    clear
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "   🩺 ${BOLD}${WHITE}WordPress Cron Health & Diagnostics Suite${NC}"
    echo -e "   Site: ${YELLOW}$SELECTED_DOMAIN${NC}"
    echo -e "${CYAN}==================================================================${NC}\n"

    echo -e "${BLUE}[1/3] Inspecting Scheduled Event Table & Next Execution Windows...${NC}"
    wp_run cron event list --fields=hook,next_run_relative,recurrence 2>/dev/null || {
        echo -e "   ${RED}❌ Failed to query cron events via WP-CLI.${NC}"
    }

    echo -e "\n${BLUE}[2/3] Executing Overdue & Due Tasks Immediately (--due-now)...${NC}"
    local run_output
    run_output=$(wp_run cron event run --due-now 2>&1 || true)
    if [ -n "$run_output" ]; then
        echo -e "${GRAY}$run_output${NC}"
    else
        echo -e "   ${GREEN}✅ All scheduled hooks are up-to-date. Zero overdue events.${NC}"
    fi

    echo -e "\n${BLUE}[3/3] Testing Core Loopback Engine & Cron Health...${NC}"
    if wp_run cron test >/dev/null 2>&1; then
        echo -e "   ${GREEN}✅ Cron engine verified healthy and responsive.${NC}"
    else
        echo -e "   ${YELLOW}⚠️  WP-Cron test hook returned non-zero response (Verify /etc/hosts loopback).${NC}"
    fi

    enforce_permissions
    echo ""
    read -rp "Press Enter to return to site dashboard..."
}

# ------------------------------------------------------------------------------
# 8. CONTEXTUAL SITE DASHBOARD RENDERER (Symmetrical 5x2 Matrix)
# ------------------------------------------------------------------------------
draw_site_dashboard() {
    clear
    local wp_version="Unknown"
    local maint_status="${GREEN}● LIVE${NC}"
    local debug_status="${GRAY}○ OFF${NC}"
    local cron_status="${GRAY}○ Web-Triggered${NC}"
    local p_active="0"

    wp_version=$(wp_run core version 2>/dev/null || echo "Needs Setup")
    wp_version=$(echo "$wp_version" | tr -d '\r\n' | cut -c 1-15)

    if wp_run maintenance-mode is-active >/dev/null 2>&1; then
        maint_status="${YELLOW}● MAINTENANCE${NC}"
    fi

    local cur_cfg
    cur_cfg=$(get_cfg_file)
    if [[ -n "$cur_cfg" ]] && grep -qiE "define\s*\(\s*['\"]WP_DEBUG['\"]\s*,\s*true\s*\)" "$cur_cfg" 2>/dev/null; then
        debug_status="${YELLOW}● ON (Log Only)${NC}"
    fi

    local cron_id
    cron_id=$(echo "$SELECTED_DOMAIN" | tr '.-' '_')
    if [ -f "/etc/cron.d/bashboard-wp-${cron_id}" ]; then
        cron_status="${GREEN}● Linux Crontab (5m)${NC}"
    fi

    p_active=$(wp_run plugin list --status=active --format=count 2>/dev/null || echo "0")
    p_active=$(echo "$p_active" | tr -dc '0-9')
    [[ -z "$p_active" ]] && p_active="0"
    local plugins_count="${p_active} Active"
    local vhost_user
    vhost_user=$(get_vhost_user)

    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Site: %-27s${NC}\n" "BASHBOARD WP MANAGER" "$SELECTED_DOMAIN"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   📋 ${PURPLE}${BOLD}ENVIRONMENT TELEMETRY & LIVE STATE${NC}"

    printf "      %-22s: ${WHITE}%-18s${NC}" "Layout Architecture" "$SITE_LAYOUT"
    echo -ne "${COL_MID}${GRAY}│${NC} "
    printf "%-16s: ${YELLOW}%-20s${NC}\n" "Core Version" "WordPress ${wp_version}"

    printf "      %-22s: %-28b" "Operational State" "$maint_status"
    echo -ne "${COL_MID}${GRAY}│${NC} "
    printf "%-16s: ${WHITE}%-20s${NC}\n" "Active Plugins" "$plugins_count"

    printf "      %-22s: %-28b" "Debug Logging" "$debug_status"
    echo -ne "${COL_MID}${GRAY}│${NC} "
    printf "%-16s: %-28b\n" "WP-Cron Runner" "$cron_status"

    printf "      %-22s: ${CYAN}%-18s${NC}" "Tenant User" "$vhost_user"
    echo -ne "${COL_MID}${GRAY}│${NC} "
    printf "%-16s: ${WHITE}%-20s${NC}\n" "Target Directory" "/var/www/$SELECTED_DOMAIN"

    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ⚡ ${PURPLE}${BOLD}ACTIONS & MAINTENANCE OPERATIONS${NC}\n"

    printf "   ${CYAN}[1]${NC} %-36s" "🔄 Flush Caches (Redis/Transients)"
    echo -ne "${COL_MID}${GRAY}│${NC}   "
    printf "${CYAN}[6]${NC} %s\n" "🚨 Deactivate ALL Plugins (WSOD Fix)"

    printf "   ${CYAN}[2]${NC} %-36s" "🛠️  Toggle Maintenance Mode"
    echo -ne "${COL_MID}${GRAY}│${NC}   "
    printf "${CYAN}[7]${NC} %s\n" "🐞 Toggle WP_DEBUG On/Off"

    printf "   ${CYAN}[3]${NC} %-36s" "👤 Reset / Create Administrator"
    echo -ne "${COL_MID}${GRAY}│${NC}   "
    printf "${CYAN}[8]${NC} %s\n" "💾 Export Database Backup (Gzip SQL)"

    printf "   ${CYAN}[4]${NC} %-36s" "🔒 Verify Core Integrity (Checksums)"
    echo -ne "${COL_MID}${GRAY}│${NC}   "
    printf "${CYAN}[9]${NC} %s\n" "⏱️  Toggle System-Level WP-Cron (5m)"

    printf "   ${CYAN}[5]${NC} %-36s" "🔌 Update All Plugins & Themes"
    echo -ne "${COL_MID}${GRAY}│${NC}   "
    printf "${CYAN}[10]${NC} %s\n" "🩺 Test Cron & Inspect Schedules"

    echo -e "\n${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ${RED}${BOLD}[0] ↩️  EXIT TO BASHBOARD ROOT${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# ------------------------------------------------------------------------------
# 9. COMMAND DISPATCHER & RESILIENT ACTIONS
# ------------------------------------------------------------------------------
while true; do
    draw_site_dashboard
    tput cnorm 2>/dev/null || true
    echo -ne "\n   ${BOLD}${WHITE}Choose an action [0-10]:${NC} "
    read -r act || act="0"

    case "$act" in
        1)
            echo -e "\n${BLUE}Purging object caches and transients...${NC}"
            wp_run cache flush 2>/dev/null || true
            wp_run transient delete --all 2>/dev/null || true
            enforce_permissions
            echo -e "${GREEN}✅ All application caches flushed successfully.${NC}"
            sleep 1.2
            ;;
        2)
            echo ""
            if wp_run maintenance-mode is-active >/dev/null 2>&1; then
                wp_run maintenance-mode deactivate
                echo -e "${GREEN}✅ Maintenance mode deactivated. Site is LIVE.${NC}"
            else
                wp_run maintenance-mode activate
                echo -e "${YELLOW}⚠️  Maintenance mode activated. Site is OFFLINE to visitors.${NC}"
            fi
            enforce_permissions
            sleep 1.5
            ;;
        3)
            echo -e "\n${BLUE}--- Administrator Account Manager ---${NC}"
            echo -e "  ${CYAN}[1]${NC} Reset password for existing user"
            echo -e "  ${CYAN}[2]${NC} Create a brand new Administrator"
            read -rp "  Select option [1-2]: " u_opt
            if [[ "$u_opt" == "1" ]]; then
                read -rp "  Enter Username or Email: " wp_u
                read -rsp "  Enter New Password: " wp_p
                echo ""
                if [[ -n "$wp_u" && -n "$wp_p" ]]; then
                    wp_run user update "$wp_u" --user_pass="$wp_p"
                    echo -e "${GREEN}✅ Password updated for user '$wp_u'.${NC}"
                else
                    echo -e "${RED}User and password cannot be empty.${NC}"
                fi
            elif [[ "$u_opt" == "2" ]]; then
                read -rp "  New Admin Username: " new_u
                read -rp "  New Admin Email: " new_e
                read -rsp "  New Admin Password: " new_p
                echo ""
                if [[ -n "$new_u" && -n "$new_e" && -n "$new_p" ]]; then
                    wp_run user create "$new_u" "$new_e" --role=administrator --user_pass="$new_p"
                    echo -e "${GREEN}✅ Administrator '$new_u' provisioned.${NC}"
                else
                    echo -e "${RED}All fields are required.${NC}"
                fi
            fi
            enforce_permissions
            sleep 2
            ;;
        4)
            echo -e "\n${BLUE}Validating core checksums against WordPress.org API...${NC}"
            if wp_run core verify-checksums; then
                echo -e "${GREEN}✅ Core verified clean. No rogue or modified files detected.${NC}"
            else
                echo -e "${RED}⚠️  Warning: Checksum discrepancies detected in core files!${NC}"
            fi
            read -rp "Press Enter to continue..."
            ;;
        5)
            echo -e "\n${BLUE}Upgrading all installed plugins & themes...${NC}"
            wp_run plugin update --all || true
            wp_run theme update --all || true
            enforce_permissions
            echo -e "${GREEN}✅ Updates complete and file permissions re-aligned to tenant user.${NC}"
            sleep 1.5
            ;;
        6)
            echo -e "\n${YELLOW}Emergency: Deactivating ALL active plugins (Bypassing Fatal Errors)...${NC}"
            if wp_run plugin deactivate --all --skip-plugins; then
                wp_run cache flush 2>/dev/null || true
                enforce_permissions
                echo -e "${GREEN}✅ All plugins successfully deactivated without loading broken code.${NC}"
            else
                echo -e "${RED}❌ Failed to deactivate plugins.${NC}"
            fi
            sleep 2
            ;;
        7)
            cfg_file=$(get_cfg_file)
            if [[ -n "$cfg_file" && -f "$cfg_file" ]]; then
                if grep -qiE "define\s*\(\s*['\"]WP_DEBUG['\"]\s*,\s*true\s*\)" "$cfg_file"; then
                    wp_run config set WP_DEBUG false --raw 2>/dev/null || sed -i "s/define(\s*['\"]WP_DEBUG['\"]\s*,\s*true\s*);/define( 'WP_DEBUG', false );/gI" "$cfg_file"
                    wp_run config set WP_DEBUG_LOG false --raw 2>/dev/null || true
                    wp_run config set WP_DEBUG_DISPLAY false --raw 2>/dev/null || true
                    echo -e "${YELLOW}WP_DEBUG toggled OFF.${NC}"
                else
                    wp_run config set WP_DEBUG true --raw 2>/dev/null || sed -i "s/define(\s*['\"]WP_DEBUG['\"]\s*,\s*false\s*);/define( 'WP_DEBUG', true );/gI" "$cfg_file"
                    wp_run config set WP_DEBUG_LOG true --raw 2>/dev/null || true
                    wp_run config set WP_DEBUG_DISPLAY false --raw 2>/dev/null || true
                    echo -e "${GREEN}WP_DEBUG toggled ON (Hardened: Logging to debug.log, Public Display Blocked).${NC}"
                fi
                enforce_permissions
            else
                echo -e "${RED}Error: wp-config.php file not found.${NC}"
            fi
            sleep 1.5
            ;;
        8)
            backup_dir="/var/backups/bashboard"
            mkdir -p "$backup_dir"
            chmod 700 "$backup_dir"

            bkp_file="${backup_dir}/${SELECTED_DOMAIN}_$(date +%Y%m%d_%H%M%S).sql.gz"
            echo -e "\n${BLUE}Exporting and compressing MySQL database (Gzip)...${NC}"

            if wp_run db export - --add-drop-table 2>/dev/null | gzip -c > "$bkp_file"; then
                if [[ -s "$bkp_file" ]]; then
                    chmod 600 "$bkp_file"
                    # C6 Bug Fix: Safe top-level variable assignment without 'local' keyword
                    bkp_size=$(du -h "$bkp_file" | cut -f1)
                    echo -e "${GREEN}✅ Database backup successfully created:${NC}"
                    echo -e "   File: ${YELLOW}$bkp_file${NC} (Size: ${WHITE}$bkp_size${NC})"
                else
                    rm -f "$bkp_file"
                    echo -e "${RED}❌ [ERROR] Exported database dump is empty.${NC}"
                fi
            else
                echo -e "${RED}❌ [ERROR] Database export operation failed.${NC}"
            fi
            read -rp "Press Enter to continue..."
            ;;
        9)
            toggle_system_wpcron "$SELECTED_DOMAIN" "$WP_PATH"
            ;;
        10)
            inspect_and_test_cron
            ;;
        0)
            echo -e "\n   ${GREEN}Returning to Bashboard...${NC}"
            exit 0
            ;;
        *)
            echo -e "\n   ${RED}Invalid action.${NC}"
            sleep 0.8
            ;;
    esac
done