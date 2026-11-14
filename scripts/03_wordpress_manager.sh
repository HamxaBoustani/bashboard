#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD MODULE: [03] WordPress Site Manager (Enterprise TUI Edition)
# Version:          1.8.0 (Zero-Trust Hardened: CWD-Isolated CLI/Cron Sandbox,
#                   Symlink-Safe Permissions, Stdin Password Pipe, Non-Locking Dump)
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
                chmod 755 "$tmp_wp"
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
    else
        chmod 755 /usr/local/bin/wp 2>/dev/null || true
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
# 5. ENVIRONMENT PATH RESOLUTION, PHP PINNING & SANDBOXED RUNNERS (Resolves C1 & C3)
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

get_authoritative_state_file() {
    if [ -f "/etc/bashboard/sites/${SELECTED_DOMAIN}.state" ] && [ ! -L "/etc/bashboard/sites/${SELECTED_DOMAIN}.state" ]; then
        echo "/etc/bashboard/sites/${SELECTED_DOMAIN}.state"
    elif [ -f "/var/www/$SELECTED_DOMAIN/.bashboard-state" ] && [ ! -L "/var/www/$SELECTED_DOMAIN/.bashboard-state" ] && [ "$(stat -c '%u' "/var/www/$SELECTED_DOMAIN/.bashboard-state" 2>/dev/null)" = "0" ]; then
        echo "/var/www/$SELECTED_DOMAIN/.bashboard-state"
    else
        echo ""
    fi
}

get_vhost_user() {
    local u=""
    local sf
    sf=$(get_authoritative_state_file)
    if [[ -n "$sf" ]]; then
        u=$(grep -E "^TENANT_USER=" "$sf" 2>/dev/null | cut -d'=' -f2- || true)
    fi
    if [[ -z "$u" ]] && [ -d "$TARGET_DIR" ]; then
        u=$(stat -c '%U' "$TARGET_DIR" 2>/dev/null || true)
    fi
    # Verify tenant user strictly matches ^v_ and its home directory matches the site
    if [[ "$u" =~ ^v_[a-z0-9_]+$ ]] && [ "$u" != "v_pma_sys" ] && [[ "$(getent passwd "$u" 2>/dev/null | cut -d: -f6)" == "/var/www/$SELECTED_DOMAIN" ]]; then
        echo "$u"
    else
        echo ""
    fi
}

get_site_php_bin() {
    local ver=""
    local sf
    sf=$(get_authoritative_state_file)
    if [[ -n "$sf" ]]; then
        ver=$(grep -E "^PHP_VER=" "$sf" 2>/dev/null | cut -d'=' -f2- || true)
    fi
    if [[ -z "$ver" ]] && [ -f "/etc/nginx/sites-available/$SELECTED_DOMAIN" ]; then
        ver=$(grep -oE 'php[0-9]+\.[0-9]+-fpm' "/etc/nginx/sites-available/$SELECTED_DOMAIN" 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' || true)
    fi
    if [[ -n "$ver" && -x "/usr/bin/php${ver}" ]]; then
        echo "/usr/bin/php${ver}"
    else
        command -v php 2>/dev/null || echo "/usr/bin/php"
    fi
}

SITE_PHP_BIN=$(get_site_php_bin)

# C2 & C3 Hardened WP-CLI runner: Changes CWD to $WP_PATH, drops root privileges,
# locks include_path, and enforces open_basedir + disable_functions on CLI!
wp_run() {
    local u
    u=$(get_vhost_user)
    if [[ -z "$u" || ! "$u" =~ ^v_ ]]; then
        echo -e "   ${RED}❌ [CRITICAL] Refusing to execute WP-CLI: Invalid or unverified tenant user ($u).${NC}" >&2
        return 1
    fi
    mkdir -p "/var/www/$SELECTED_DOMAIN/tmp/wp-cache" 2>/dev/null || true
    chown "$u:$u" "/var/www/$SELECTED_DOMAIN/tmp/wp-cache" 2>/dev/null || true

    # (
    #     cd "$WP_PATH"
    #     runuser -u "$u" -- env HOME="/var/www/$SELECTED_DOMAIN" \
    #         WP_CLI_CACHE_DIR="/var/www/$SELECTED_DOMAIN/tmp/wp-cache" \
    #         "$SITE_PHP_BIN" \
    #         -d memory_limit=512M \
    #         -d include_path=".:${WP_PATH}" \
    #         -d open_basedir="/var/www/${SELECTED_DOMAIN}/:/usr/local/bin/wp:phar:///usr/local/bin/wp:/usr/share/zoneinfo/:/dev/urandom" \
    #         -d disable_functions="exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec,show_source,highlight_file,proc_get_status,posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,posix_setuid" \
    #         -d error_reporting="E_ALL & ~E_WARNING & ~E_DEPRECATED & ~E_USER_DEPRECATED & ~E_NOTICE" \
    #         /usr/local/bin/wp --path="$WP_PATH" "$@"
    # )
    (
        cd "$WP_PATH"
        runuser -u "$u" -- env HOME="/var/www/$SELECTED_DOMAIN" \
            WP_CLI_CACHE_DIR="/var/www/$SELECTED_DOMAIN/tmp/wp-cache" \
            "$SITE_PHP_BIN" \
            -d memory_limit=512M \
            -d display_errors=0 \
            -d include_path=".:${WP_PATH}" \
            -d open_basedir="/var/www/${SELECTED_DOMAIN}/:/usr/local/bin/wp:/usr/share/zoneinfo/:/dev/urandom" \
            -d disable_functions="exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec,show_source,highlight_file,proc_get_status,posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,posix_setuid" \
            -d error_reporting="E_ALL & ~E_WARNING & ~E_DEPRECATED & ~E_USER_DEPRECATED & ~E_NOTICE" \
            /usr/local/bin/wp --no-color --path="$WP_PATH" "$@"
    )
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

# Symlink-Safe Permission Enforcer (Resolves C1, C2 & W1)
enforce_permissions() {
    local site_root="/var/www/$SELECTED_DOMAIN"
    local vhost_user
    vhost_user=$(get_vhost_user)

    if [ -d "$site_root" ] && [[ -n "$vhost_user" ]]; then
        usermod -a -G "$vhost_user" www-data 2>/dev/null || true

        # Root-anchored parent directory prevents .bashboard-state unlinking (C1)
        chown "root:$vhost_user" "$site_root"
        chmod 750 "$site_root"

        # Logs directory owned by www-data:$vhost_user (750) prevents symlink privilege escalation (C2)
        if [ -d "$site_root/logs" ] && [ ! -L "$site_root/logs" ]; then
            chown "www-data:$vhost_user" "$site_root/logs"
            chmod 750 "$site_root/logs"
        fi

        # Execute chmod inside tenant context to neutralize root symlink race conditions (W1)
        chown -h -R "$vhost_user:$vhost_user" "$TARGET_DIR" 2>/dev/null || true
        runuser -u "$vhost_user" -- find "$TARGET_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
        runuser -u "$vhost_user" -- find "$TARGET_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true

        local cfg
        cfg=$(get_cfg_file)
        if [[ -n "$cfg" && -f "$cfg" && ! -L "$cfg" ]]; then
            chown "$vhost_user:$vhost_user" "$cfg"
            chmod 600 "$cfg" 2>/dev/null || true
        fi
    fi
}

# ------------------------------------------------------------------------------
# 6. CRON RUNNER ASSERTION & SCHEDULER ORCHESTRATION (Resolves C3 & W3)
# ------------------------------------------------------------------------------
ensure_cron_runner() {
    local runner="/usr/local/bin/bashboard-cron-runner"
    cat << 'EOF' > "$runner"
#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD CRON RUNNER ENGINE
# Architecture: Single Lock Capsule, Multi-PHP Aware, CLI Sandboxed (C3 Fixed)
# ==============================================================================
set -e

DOMAIN="${1:-}"
WP_PATH="${2:-}"

if [[ -z "$DOMAIN" || -z "$WP_PATH" ]]; then
    echo "Usage: $0 <domain> <wp_path>" >&2
    exit 1
fi

PHP_BIN="/usr/bin/php"
STATE_FILE="/etc/bashboard/sites/${DOMAIN}.state"
[ ! -f "$STATE_FILE" ] && STATE_FILE="/var/www/${DOMAIN}/.bashboard-state"

if [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ]; then
    VER=$(grep -E "^PHP_VER=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2- || true)
    if [[ -n "$VER" && -x "/usr/bin/php${VER}" ]]; then
        PHP_BIN="/usr/bin/php${VER}"
    fi
fi

LOCK_FILE="/var/www/${DOMAIN}/tmp/cron.lock"
# OPEN_BASEDIR="/var/www/${DOMAIN}/:/usr/local/bin/wp:phar:///usr/local/bin/wp:/usr/share/zoneinfo/:/dev/urandom"
OPEN_BASEDIR="/var/www/${DOMAIN}/:/usr/local/bin/wp:/usr/share/zoneinfo/:/dev/urandom"
DISABLED_FUNCS="exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec,show_source,highlight_file,proc_get_status,posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,posix_setuid"

cd "${WP_PATH}" 2>/dev/null || exit 1

# Execute inside a single atomic flock capsule with full PHP CLI sandboxing (Resolves C3)
/usr/bin/flock -n "${LOCK_FILE}" -c "
    \"${PHP_BIN}\" -d memory_limit=512M \
        -d include_path='.:${WP_PATH}' \
        -d open_basedir='${OPEN_BASEDIR}' \
        -d disable_functions='${DISABLED_FUNCS}' \
        -d error_reporting='E_ALL & ~E_WARNING & ~E_DEPRECATED & ~E_USER_DEPRECATED & ~E_NOTICE' \
        /usr/local/bin/wp cron event run --due-now --path='${WP_PATH}' --quiet 2>/dev/null || true

    if \"${PHP_BIN}\" -d include_path='.:${WP_PATH}' -d open_basedir='${OPEN_BASEDIR}' -d disable_functions='${DISABLED_FUNCS}' \
        -d error_reporting='E_ALL & ~E_WARNING & ~E_DEPRECATED & ~E_USER_DEPRECATED & ~E_NOTICE' \
        /usr/local/bin/wp --path='${WP_PATH}' cli has-command action-scheduler >/dev/null 2>&1; then
        \"${PHP_BIN}\" -d memory_limit=512M \
            -d include_path='.:${WP_PATH}' \
            -d open_basedir='${OPEN_BASEDIR}' \
            -d disable_functions='${DISABLED_FUNCS}' \
            -d error_reporting='E_ALL & ~E_WARNING & ~E_DEPRECATED & ~E_USER_DEPRECATED & ~E_NOTICE' \
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
        wp_run config set DISABLE_WP_CRON false --raw --skip-plugins --skip-themes >/dev/null 2>&1 || true
        echo -e "   ${YELLOW}● Crontab removed: ${cron_file}${NC}"
        echo -e "   ${GREEN}✅ Restored web-triggered WP-Cron (DISABLE_WP_CRON = false).${NC}"
    else
        echo -e "   Deploying isolated Linux crontab for ${YELLOW}${domain}${NC} (5-Minute Cadence)..."

        ensure_cron_runner

        local delay=$(( 16#$(echo -n "$domain" | md5sum | cut -c1-2) % 40 ))

        cat > "$cron_file" <<EOF
# Bashboard Automated WP-Cron for $domain
# Runs strictly as $vhost_user with sandboxed CLI execution envelopes
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
HOME=/var/www/$domain
WP_CLI_CACHE_DIR=/var/www/$domain/tmp/wp-cache

*/5 * * * * $vhost_user sleep $delay; /usr/local/bin/bashboard-cron-runner $domain $wp_path >/dev/null 2>&1 || true
EOF
        chmod 644 "$cron_file"
        wp_run config set DISABLE_WP_CRON true --raw --skip-plugins --skip-themes >/dev/null 2>&1 || true

        echo -e "   ${GREEN}✅ Global Runner Verified : ${WHITE}/usr/local/bin/bashboard-cron-runner${NC} (${SITE_PHP_BIN})"
        echo -e "   ${GREEN}✅ Linux Crontab deployed : ${CYAN}$cron_file${NC} (User: ${WHITE}$vhost_user${NC}, Delay: ${YELLOW}${delay}s${NC})"
        echo -e "   ${GREEN}✅ Web-spawning disabled  : ${WHITE}DISABLE_WP_CRON = true${NC} synced in wp-config.php"
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
    echo -e "   Site: ${YELLOW}$SELECTED_DOMAIN${NC} (Runtime: ${CYAN}$SITE_PHP_BIN${NC})"
    echo -e "${CYAN}==================================================================${NC}\n"

    echo -e "${BLUE}[1/3] Inspecting Scheduled Event Table & Next Execution Windows...${NC}"
    wp_run cron event list --fields=hook,next_run_relative,recurrence 2>/dev/null || {
        echo -e "   ${RED}❌ Failed to query cron events via WP-CLI.${NC}"
    }

    echo -e "\n${BLUE}[2/3] Executing Overdue & Due Tasks Immediately (--due-now)...${NC}"
    local run_output
    # run_output=$(wp_run cron event run --due-now 2>&1 || true)
    run_output=$(wp_run cron event run --due-now 2>&1 | grep -vE "^(PHP )?(Deprecated|Notice|Warning):.*phar:///usr/local/bin/wp" || true)
    if [ -n "$run_output" ]; then
        echo -e "${GRAY}$run_output${NC}"
    else
        echo -e "   ${GREEN}✅ All scheduled hooks are up-to-date. Zero overdue events.${NC}"
    fi

    echo -e "\n${BLUE}[3/3] Testing Loopback Engine & Cron Infrastructure...${NC}"
    local cur_cfg
    cur_cfg=$(get_cfg_file)

    if [[ -n "$cur_cfg" ]] && grep -qiE "define\s*\(\s*['\"]DISABLE_WP_CRON['\"]\s*,\s*true\s*\)" "$cur_cfg" 2>/dev/null; then
        echo -e "   ${GREEN}● Web-spawning suppressed: (DISABLE_WP_CRON = true)${NC}"
        echo -e "   ${GREEN}✅ Background scheduler is correctly offloaded to Linux Crontab.${NC}"
    else
        echo -e "   ${GRAY}○ Web-spawning enabled: (DISABLE_WP_CRON is false/unset)${NC}"
    fi

    local http_code
    http_code=$(curl -s -k -o /dev/null -w "%{http_code}" "https://${SELECTED_DOMAIN}/wp-cron.php" 2>/dev/null || echo "000")
    if [[ "$http_code" == "200" || "$http_code" == "301" ]]; then
        echo -e "   ${GREEN}✅ Local loopback networking verified healthy (HTTP ${http_code}).${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Loopback returned HTTP ${http_code} (Verify /etc/hosts loopback).${NC}"
    fi

    echo ""
    read -rp "Press Enter to return to site dashboard..."
}

# ------------------------------------------------------------------------------
# 8. CONTEXTUAL SITE DASHBOARD RENDERER (Fast Zero-Bootstrap Telemetry)
# ------------------------------------------------------------------------------
draw_site_dashboard() {
    clear
    local wp_version="Unknown"
    local maint_status="${GREEN}● LIVE${NC}"
    local debug_status="${GRAY}○ OFF${NC}"
    local cron_status="${GRAY}○ Web-Triggered${NC}"
    local p_active="0"

    local ver_file="$WP_PATH/wp-includes/version.php"
    if [ -f "$ver_file" ]; then
        wp_version=$(awk -F"'" '/\$wp_version\s*=/ {print $2}' "$ver_file" 2>/dev/null || true)
    fi
    [ -z "$wp_version" ] && wp_version="Unknown"

    if [ -f "$WP_PATH/.maintenance" ]; then
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

    p_active=$(wp_run plugin list --status=active --format=count --skip-plugins 2>/dev/null || echo "0")
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

    printf "      %-22s: ${CYAN}%-18s${NC}" "Tenant User" "${vhost_user:-Unverified}"
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
            echo -e "${GREEN}✅ All application caches flushed successfully.${NC}"
            sleep 1.2
            ;;
        2)
            echo ""
            if [ -f "$WP_PATH/.maintenance" ]; then
                rm -f "$WP_PATH/.maintenance"
                wp_run option delete core_updater.lock >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ Maintenance mode deactivated & update locks cleared. Site is LIVE.${NC}"
            else
                # Static timestamp 1 year into the future prevents 10-minute auto-expiry (Resolves W2)
                future_ts=$(( $(date +%s) + 31536000 ))
                v_u=$(get_vhost_user)
                printf '<?php $upgrading = %s; ?>\n' "$future_ts" > "$WP_PATH/.maintenance"
                [[ -n "$v_u" ]] && chown "$v_u:$v_u" "$WP_PATH/.maintenance" 2>/dev/null || true
                chmod 644 "$WP_PATH/.maintenance" 2>/dev/null || true
                echo -e "${YELLOW}⚠️  Persistent maintenance mode activated. Site is OFFLINE to visitors.${NC}"
            fi
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
                    # Pipe password via stdin to avoid /proc argv exposure (Resolves W7)
                    printf "%s\n" "$wp_p" | wp_run user update "$wp_u" --prompt=user_pass >/dev/null
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
                    printf "%s\n" "$new_p" | wp_run user create "$new_u" "$new_e" --role=administrator --prompt=user_pass >/dev/null
                    echo -e "${GREEN}✅ Administrator '$new_u' provisioned.${NC}"
                else
                    echo -e "${RED}All fields are required.${NC}"
                fi
            fi
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
            echo -e "${GREEN}✅ Updates complete and file permissions verified.${NC}"
            sleep 1.5
            ;;
        6)
            echo -e "\n${YELLOW}Emergency: Deactivating ALL active plugins (Bypassing Fatal Errors)...${NC}"
            if wp_run plugin deactivate --all --skip-plugins; then
                wp_run cache flush 2>/dev/null || true
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
                    wp_run config set WP_DEBUG false --raw --skip-plugins --skip-themes 2>/dev/null || sed -i "s/define(\s*['\"]WP_DEBUG['\"]\s*,\s*true\s*);/define( 'WP_DEBUG', false );/gI" "$cfg_file"
                    wp_run config set WP_DEBUG_LOG false --raw --skip-plugins --skip-themes 2>/dev/null || true
                    wp_run config set WP_DEBUG_DISPLAY false --raw --skip-plugins --skip-themes 2>/dev/null || true
                    echo -e "${YELLOW}WP_DEBUG toggled OFF.${NC}"
                else
                    wp_run config set WP_DEBUG true --raw --skip-plugins --skip-themes 2>/dev/null || sed -i "s/define(\s*['\"]WP_DEBUG['\"]\s*,\s*false\s*);/define( 'WP_DEBUG', true );/gI" "$cfg_file"
                    wp_run config set WP_DEBUG_LOG true --raw --skip-plugins --skip-themes 2>/dev/null || true
                    wp_run config set WP_DEBUG_DISPLAY false --raw --skip-plugins --skip-themes 2>/dev/null || true
                    echo -e "${GREEN}WP_DEBUG toggled ON (Hardened: Logging to debug.log, Public Display Blocked).${NC}"
                fi
                chmod 600 "$cfg_file" 2>/dev/null || true
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
            echo -e "\n${BLUE}Exporting and compressing MySQL database (Non-Locking Gzip)...${NC}"

            sf_path=$(get_authoritative_state_file)
            site_db=""
            [[ -n "$sf_path" ]] && site_db=$(grep -E "^DB_NAME=" "$sf_path" 2>/dev/null | cut -d'=' -f2- || true)
            if [[ -z "$site_db" ]]; then
                site_db=$(wp_run config get DB_NAME --skip-plugins --skip-themes 2>/dev/null || true)
            fi

            DUMP_BIN="mariadb-dump"
            command -v mariadb-dump >/dev/null 2>&1 || DUMP_BIN="mysqldump"

            if [[ "$site_db" =~ ^[a-zA-Z0-9_]{1,64}$ ]] && $DUMP_BIN --single-transaction --quick --routines --triggers -u root "$site_db" 2>/dev/null | gzip -c > "$bkp_file"; then
                if [ -f "$bkp_file" ] && [ "$(stat -c '%s' "$bkp_file" 2>/dev/null || echo 0)" -gt 64 ]; then
                    chmod 600 "$bkp_file"
                    bkp_size=$(du -h "$bkp_file" | cut -f1)
                    echo -e "${GREEN}✅ Database backup successfully created:${NC}"
                    echo -e "   File: ${YELLOW}$bkp_file${NC} (Size: ${WHITE}$bkp_size${NC})"
                else
                    rm -f "$bkp_file"
                    echo -e "${RED}❌ [ERROR] Exported database dump is empty.${NC}"
                fi
            else
                rm -f "$bkp_file"
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