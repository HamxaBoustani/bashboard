#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD MODULE: [02] Nginx Virtual Host & Architecture Deployer (TUI Edition)
# Version:          1.8.0 (Zero-Trust Hardened: Root-Anchored Tenant Dir, CVE-2016-1247
#                   Log Symlink Guard, Hashed DB/Pool Names, Webroot ACME TLS)
# Architecture:     Interactive TUI Configurator | Commercial Hosting Standard
# Platform:         Debian 11/12, Ubuntu 20.04/22.04/24.04/26.04 LTS
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

# ------------------------------------------------------------------------------
# 2. RUNTIME DEPENDENCY ASSERTION
# ------------------------------------------------------------------------------
DB_BIN="mariadb"
if ! command -v mariadb >/dev/null 2>&1; then
    if command -v mysql >/dev/null 2>&1; then
        DB_BIN="mysql"
    else
        echo -e "${RED}❌ [FATAL] Database client (mariadb/mysql) is missing.${NC}" >&2
        exit 1
    fi
fi

for cmd in nginx wget unzip curl openssl sed awk getent hostname useradd groupadd usermod wp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}❌ [FATAL] Missing required core utility: '$cmd'. Provision LEMP stack first.${NC}" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# 3. DYNAMIC PHP SOCKET AUTODISCOVERY
# ------------------------------------------------------------------------------
detect_installed_phps() {
    local phps=()
    for sock in /run/php/php*-fpm.sock /var/run/php/php*-fpm.sock; do
        if [ -S "$sock" ]; then
            local ver
            ver=$(basename "$sock" | grep -oE '[0-9]+\.[0-9]+' || true)
            [[ -n "$ver" ]] && phps+=("$ver")
        fi
    done
    if [ -d "/etc/php" ]; then
        for d in /etc/php/*; do
            if [ -d "$d" ]; then
                local b
                b=$(basename "$d")
                [[ "$b" =~ ^[0-9]+\.[0-9]+$ ]] && phps+=("$b")
            fi
        done
    fi
    if [ ${#phps[@]} -gt 0 ]; then
        printf "%s\n" "${phps[@]}" | sort -uV | paste -sd "," -
    else
        echo ""
    fi
}

AVAILABLE_PHPS=$(detect_installed_phps)
DEFAULT_PHP=$(echo "$AVAILABLE_PHPS" | awk -F',' '{print $NF}' | tr -d '[:space:]')
[[ -z "$DEFAULT_PHP" ]] && DEFAULT_PHP="8.3"

# ------------------------------------------------------------------------------
# 4. CONFIGURATION DEFAULTS & VALIDATION HELPERS
# ------------------------------------------------------------------------------
DOMAIN=""
PHP_VER="$DEFAULT_PHP"
PAYLOAD_TYPE="wordpress" # 'wordpress' or 'blank'
ENABLE_MEDIA_SUBDOMAIN=0 # 1: Yes (uploads.domain), 0: No
ENABLE_LETSENCRYPT=1     # 1: Pre-flight DNS & Certbot, 0: Self-signed only
DB_NAME=""
DB_USER=""
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
MYSQL_ADMIN="root"
MYSQL_ADMIN_PASS=""

validate_domain() {
    local d="$1"
    [[ -z "$d" ]] && return 1
    local regex="^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$"
    [[ "$d" =~ $regex && "${#d}" -le 253 ]]
}

toggle_status() {
    local val="$1"
    if [ "$val" -eq 1 ]; then
        echo -e "${GREEN}[✔] ENABLED ${NC}"
    else
        echo -e "${GRAY}[ ] DISABLED${NC}"
    fi
}

detect_nginx_http2_mode() {
    local raw_ver major minor patch
    raw_ver=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || echo "1.18.0")
    major=$(echo "$raw_ver" | cut -d. -f1)
    minor=$(echo "$raw_ver" | cut -d. -f2)
    patch=$(echo "$raw_ver" | cut -d. -f3)
    patch=${patch:-0}

    if [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -gt 25 ]; } || { [ "$major" -eq 1 ] && [ "$minor" -eq 25 ] && [ "$patch" -ge 1 ]; }; then
        echo "modern"
    else
        echo "legacy"
    fi
}

calculate_safe_max_children() {
    local mem_total_kb mem_total_mb reserved_ram usable_ram safe_children
    mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo "2097152")
    mem_total_mb=$(( mem_total_kb / 1024 ))

    local vhost_count=1
    if [ -d "/etc/nginx/sites-available" ]; then
        vhost_count=$(find /etc/nginx/sites-available -maxdepth 1 -type f ! -name "default" 2>/dev/null | wc -l)
        vhost_count=$(( vhost_count + 1 ))
    fi

    reserved_ram=$(( mem_total_mb * 20 / 100 ))
    [ "$reserved_ram" -lt 1536 ] && reserved_ram=1536
    usable_ram=$(( mem_total_mb - reserved_ram ))
    [ "$usable_ram" -lt 512 ] && usable_ram=512

    safe_children=$(( usable_ram / (60 * vhost_count) ))
    [ "$safe_children" -lt 4 ] && safe_children=4
    [ "$safe_children" -gt 25 ] && safe_children=25
    echo "$safe_children"
}

rebalance_all_pools() {
    local target_workers
    target_workers=$(calculate_safe_max_children)
    shopt -s nullglob
    local pools=( /etc/php/*/fpm/pool.d/*.conf )
    shopt -u nullglob

    for p in "${pools[@]}"; do
        local bname
        bname=$(basename "$p")
        if [[ "$bname" != "www.conf" && "$bname" != "phpmyadmin.conf" ]]; then
            sed -i -E "s/^(pm\.max_children\s*=\s*)[0-9]+/\1${target_workers}/" "$p" 2>/dev/null || true
        fi
    done

    for fpm_bin in /usr/sbin/php-fpm*; do
        if [ -x "$fpm_bin" ]; then
            if ! "$fpm_bin" -t >/dev/null 2>&1; then
                echo -e "   ${RED}⚠️  [WARNING] FPM syntax check failed during rebalance. Reload aborted.${NC}" >&2
                return 0
            fi
        fi
    done

    for fpm in $(systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -iE '^php[0-9.]*-fpm\.service$'); do
        if systemctl is-active --quiet "$fpm" 2>/dev/null; then
            systemctl reload "$fpm" 2>/dev/null || true
        fi
    done
}

# Executes MariaDB queries securely without exposing admin password in /proc argv
run_mysql_admin() {
    if [ -n "$MYSQL_ADMIN_PASS" ]; then
        MYSQL_PWD="$MYSQL_ADMIN_PASS" "$DB_BIN" -u "$MYSQL_ADMIN" "$@"
    else
        "$DB_BIN" -u "$MYSQL_ADMIN" "$@"
    fi
}

# ------------------------------------------------------------------------------
# 5. TUI CONFIGURATOR INTERFACE
# ------------------------------------------------------------------------------
draw_vhost_tui() {
    clear
    local domain_disp="${YELLOW}${DOMAIN:-<Press [1] to Define>}${NC}"
    local payload_disp="${GREEN}Standard WordPress (Direct Updates)${NC}"
    if [ "$PAYLOAD_TYPE" == "blank" ]; then
        payload_disp="${PURPLE}Blank Site (Placeholder Only)${NC}"
    fi

    local media_sub_disp="uploads.${DOMAIN:-example.com}"
    local ssl_disp="${GREEN}Let's Encrypt (Webroot ACME)${NC}"
    if [ "$ENABLE_LETSENCRYPT" -eq 0 ]; then
        ssl_disp="${YELLOW}Self-Signed Fallback Only${NC}"
    fi

    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Module: %-25s${NC}\n" "BASHBOARD VHOST SUITE" "Virtual Host Provisioner"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   📋 ${PURPLE}${BOLD}VIRTUAL HOST TOPOLOGY & CONFIGURATION MATRIX${NC}"
    echo -e "      Configure the virtual host parameters before executing server changes."
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    printf "   ${CYAN}[1]${NC} %-26s: %-32b ${COL_MID}${GRAY}│${NC} TLS Mode : %b\n" "Target Domain Name" "$domain_disp" "$ssl_disp"
    printf "   ${CYAN}[2]${NC} %-26s: ${YELLOW}Dedicated Pool (v%s)${NC} ${COL_MID}${GRAY}│${NC} Multi-Tenancy: ${GREEN}Sandboxed POSIX User${NC}\n" "PHP Architecture" "$PHP_VER"
    printf "   ${CYAN}[3]${NC} %-26s: %-32b ${COL_MID}${GRAY}│${NC} Target   : ${WHITE}/var/www/%s${NC}\n" "Application Payload" "$payload_disp" "${DOMAIN:-<domain>}"
    printf "   ${CYAN}[4]${NC} %-26s: %b ${COL_MID}${GRAY}│${NC} Host     : ${WHITE}%s${NC}\n" "Uploads Subdomain" "$(toggle_status "$ENABLE_MEDIA_SUBDOMAIN")" "$media_sub_disp"
    printf "   ${CYAN}[5]${NC} %-26s: %b ${COL_MID}${GRAY}│${NC} Rate-Limit Guard: ${GREEN}Active${NC}\n" "Let's Encrypt TLS" "$(toggle_status "$ENABLE_LETSENCRYPT")"

    if [ "$PAYLOAD_TYPE" == "wordpress" ]; then
        echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
        echo -e "   💾 ${PURPLE}${BOLD}DATABASE ORCHESTRATION (WordPress Auto-Setup)${NC}"
        local db_disp="${YELLOW}${DB_NAME:-Auto-Generated}${NC}"
        printf "      %-23s: %-32b ${COL_MID}${GRAY}│${NC} DB User  : ${YELLOW}%s${NC}\n" "Database Name" "$db_disp" "${DB_USER:-Auto-Generated}"
        local pass_status="Auto-Socket Auth"
        if [ -n "$MYSQL_ADMIN_PASS" ]; then pass_status="Configured (Hidden)"; fi
        printf "   ${CYAN}[6]${NC} %-23s: ${YELLOW}%-22s${NC} ${COL_MID}${GRAY}│${NC} Admin    : ${CYAN}%s${NC}\n" "MySQL Admin Password" "$pass_status" "$MYSQL_ADMIN"
    fi

    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ${GREEN}${BOLD}[9] ⚡ EXECUTE PROVISIONING & DEPLOYMENT${NC}"
    echo -e "   ${RED}${BOLD}[0] ↩️  CANCEL AND RETURN TO BASHBOARD${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# ------------------------------------------------------------------------------
# 6. CONFIGURATION INPUT LOOP
# ------------------------------------------------------------------------------
while true; do
    draw_vhost_tui
    tput cnorm 2>/dev/null || true
    echo -ne "\n   ${BOLD}${WHITE}Choose an option to modify [0-9]:${NC} "
    read -r opt || opt="0"

    case "$opt" in
        1)
            echo ""
            while true; do
                read -rp "   Enter Target Domain (e.g., mysite.local, example.com): " raw_d
                raw_d=$(echo "$raw_d" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
                if validate_domain "$raw_d"; then
                    DOMAIN="$raw_d"
                    clean_slug=$(echo "$DOMAIN" | tr '.-' '_')
                    d_hash=$(echo -n "$DOMAIN" | md5sum | cut -c1-4)
                    # Collision-resistant hashed identifiers (Resolves C5)
                    DB_NAME="${clean_slug:0:20}_${d_hash}"
                    DB_USER="u_${clean_slug:0:8}_${d_hash}"
                    break
                else
                    echo -e "   ${RED}Invalid domain syntax. Use standard FQDN without protocols.${NC}"
                fi
            done
            ;;
        2)
            echo -e "\n   ${CYAN}Detected Active PHP Engines:${NC} ${AVAILABLE_PHPS:-None}"
            read -rp "   Enter Target PHP Version (e.g. 7.4, 8.1, 8.2, 8.3, 8.4, 8.5): " raw_php
            raw_php=$(echo "$raw_php" | tr -d '[:space:]')
            if [[ "$raw_php" =~ ^[789]\.[0-9]+$ ]] && [ -x "/usr/sbin/php-fpm${raw_php}" ]; then
                PHP_VER="$raw_php"
            else
                echo -e "   ${RED}PHP ${raw_php} FPM binary (/usr/sbin/php-fpm${raw_php}) is not installed! Keeping $PHP_VER.${NC}"
                sleep 1.8
            fi
            ;;
        3)
            if [ "$PAYLOAD_TYPE" == "wordpress" ]; then
                PAYLOAD_TYPE="blank"
            else
                PAYLOAD_TYPE="wordpress"
            fi
            ;;
        4)
            ENABLE_MEDIA_SUBDOMAIN=$(( 1 - ENABLE_MEDIA_SUBDOMAIN ))
            ;;
        5)
            ENABLE_LETSENCRYPT=$(( 1 - ENABLE_LETSENCRYPT ))
            ;;
        6)
            if [ "$PAYLOAD_TYPE" == "wordpress" ]; then
                echo ""
                read -rp "   MySQL Admin Username [default: root]: " user_admin
                MYSQL_ADMIN="${user_admin:-root}"
                read -rsp "   MySQL Admin Password (leave blank if unix_socket is active): " user_pass
                echo ""
                MYSQL_ADMIN_PASS="$user_pass"
            fi
            ;;
        9)
            if [ -z "$DOMAIN" ]; then
                echo -e "\n   ${RED}Error: You must configure a Target Domain first! [Option 1]${NC}"
                sleep 1.8
                continue
            fi
            if [ ! -x "/usr/sbin/php-fpm${PHP_VER}" ]; then
                echo -e "\n   ${RED}Error: PHP-FPM v${PHP_VER} is not installed! Provision it in Option [1] first.${NC}"
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

# ------------------------------------------------------------------------------
# 7. SRE ATOMIC ROLLBACK TRAP & C5 PRE-FLIGHT COLLISION GUARDS
# ------------------------------------------------------------------------------
clean_slug=$(echo "$DOMAIN" | tr '.-' '_')
domain_hash=$(echo -n "$DOMAIN" | md5sum | cut -c1-4)
pool_name="${clean_slug:0:22}_${domain_hash}"
vhost_user="v_${clean_slug:0:10}_${domain_hash}"
dedicated_sock="/run/php/php${PHP_VER}-fpm-${pool_name}.sock"

if [ -d "/var/www/$DOMAIN" ] || [ -f "/etc/nginx/sites-available/$DOMAIN" ] || [ -f "/etc/nginx/sites-enabled/$DOMAIN" ] || [ -f "/etc/php/${PHP_VER}/fpm/pool.d/${pool_name}.conf" ]; then
    echo -e "\n   ${RED}❌ [FATAL] Virtual Host or FPM Pool for '$DOMAIN' already exists on this server!${NC}" >&2
    echo -e "   ${YELLOW}Aborting to prevent destructive overwrite or accidental rollback.${NC}" >&2
    exit 1
fi

# Authenticate DB & check pre-existence BEFORE starting provisioning (Resolves C5)
DB_PREEXISTED=0
if [ "$PAYLOAD_TYPE" == "wordpress" ]; then
    if ! run_mysql_admin -e "SELECT 1;" >/dev/null 2>&1; then
        echo -e "\n   ${YELLOW}⚠️  Database authentication requires credentials.${NC}"
        read -rsp "   Enter MySQL/MariaDB password for '$MYSQL_ADMIN': " MYSQL_ADMIN_PASS
        echo ""
        if ! run_mysql_admin -e "SELECT 1;" >/dev/null 2>&1; then
            echo -e "   ${RED}❌ [FATAL] MariaDB authentication failed! Aborting.${NC}" >&2
            exit 1
        fi
    fi

    check_db_out=$(run_mysql_admin -Nse "SHOW DATABASES LIKE '$DB_NAME';" 2>/dev/null || true)
    check_user_out=$(run_mysql_admin -Nse "SELECT User FROM mysql.user WHERE User='$DB_USER' AND Host='localhost';" 2>/dev/null || true)
    if [[ -n "$check_db_out" || -n "$check_user_out" ]]; then
        echo -e "\n   ${RED}❌ [FATAL] Database '$DB_NAME' or DB User '$DB_USER' already exists!${NC}" >&2
        echo -e "   ${YELLOW}Aborting to prevent cross-tenant database collision.${NC}" >&2
        exit 1
    fi
fi

PROVISIONING_STARTED=0

rollback_on_failure() {
    local lineno="$1"
    local exit_code="$2"
    if [ "$PROVISIONING_STARTED" -eq 1 ]; then
        echo -e "\n   ${RED}❌ [CRITICAL] Provisioning aborted at line $lineno (Exit code: $exit_code).${NC}" >&2
        echo -e "   ${YELLOW}Initiating automated atomic rollback to preserve server integrity...${NC}" >&2

        rm -f "/etc/nginx/sites-enabled/$DOMAIN" "/etc/nginx/sites-available/$DOMAIN"
        rm -f "/etc/nginx/ssl/$DOMAIN.crt" "/etc/nginx/ssl/$DOMAIN.key"
        rm -f "/etc/logrotate.d/vhost-$DOMAIN"
        rm -f "/etc/bashboard/sites/${DOMAIN}.state"
        sed -i "/[[:space:]]${DOMAIN}\([[:space:]]\|$\)/d" /etc/hosts 2>/dev/null || true
        nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true

        rm -f "/etc/php/${PHP_VER}/fpm/pool.d/${pool_name}.conf" "$dedicated_sock"
        systemctl reload "php${PHP_VER}-fpm" 2>/dev/null || systemctl restart "php${PHP_VER}-fpm" 2>/dev/null || true

        if [ "$PAYLOAD_TYPE" == "wordpress" ] && [ -n "${DB_NAME:-}" ] && [ "$DB_PREEXISTED" -eq 0 ]; then
            run_mysql_admin -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; DROP USER IF EXISTS '$DB_USER'@'localhost';" 2>/dev/null || true
        fi

        rm -rf "/var/www/$DOMAIN"
        gpasswd -d www-data "$vhost_user" >/dev/null 2>&1 || true
        userdel -f "$vhost_user" 2>/dev/null || true
        groupdel "$vhost_user" 2>/dev/null || true

        echo -e "   ${GREEN}✅ Rollback complete: Staged artifacts safely purged.${NC}" >&2
    fi
    exit "$exit_code"
}
trap 'rollback_on_failure $LINENO $?' ERR

PROVISIONING_STARTED=1

# ==============================================================================
# 8. EXECUTION PHASE: VHOST & RESOURCE ISOLATION
# ==============================================================================
clear
echo -e "${CYAN}==================================================================${NC}"
echo -e "   🚀 ${BOLD}${WHITE}Provisioning Commercial-Grade VHost for:${NC} ${YELLOW}$DOMAIN${NC}"
echo -e "${CYAN}==================================================================${NC}\n"

project_root="/var/www/$DOMAIN/public_html"
logs_dir="/var/www/$DOMAIN/logs"
tmp_dir="/var/www/$DOMAIN/tmp"
nginx_conf="/etc/nginx/sites-available/$DOMAIN"
media_root="$project_root/uploads"
[ "$ENABLE_MEDIA_SUBDOMAIN" -eq 0 ] && media_root="$project_root/wp-content/uploads"

# 8.1 Idempotent Tenant User Provisioning
echo -e "   [1/8] Provisioning dedicated unprivileged tenant identity: ${CYAN}${vhost_user}${NC}..."

if ! getent group "$vhost_user" >/dev/null 2>&1; then
    groupadd -r "$vhost_user"
fi

if ! id -u "$vhost_user" >/dev/null 2>&1; then
    useradd -r -g "$vhost_user" -s /usr/sbin/nologin -d "/var/www/$DOMAIN" -M "$vhost_user"
fi

# Grant www-data traversal membership into tenant's primary group
usermod -a -G "$vhost_user" www-data

# 8.2 Prepare Directory Hierarchy, Temp Sandbox & TLS Certificates
mkdir -p "$project_root" "$logs_dir" "$tmp_dir" "/etc/nginx/ssl" "/etc/bashboard/sites"
chmod 700 "/etc/bashboard" "/etc/bashboard/sites"
[[ "$ENABLE_MEDIA_SUBDOMAIN" -eq 1 ]] && mkdir -p "$media_root"

chown -R "$vhost_user:$vhost_user" "$tmp_dir"
chmod 700 "$tmp_dir"

cert_file="/etc/nginx/ssl/$DOMAIN.crt"
key_file="/etc/nginx/ssl/$DOMAIN.key"
if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
    echo -e "   [2/8] Generating self-signed TLS fallback certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key_file" -out "$cert_file" \
        -subj "/C=US/ST=Dev/L=Infrastructure/O=Bashboard/CN=$DOMAIN" 2>/dev/null
    chmod 600 "$key_file"
fi

# 8.3 Configure PHP-FPM Pool Safely (Test Before Reload - Resolves W4)
safe_max_workers=$(calculate_safe_max_children)

configure_isolated_php_pool() {
    local domain="$1"
    local php_ver="$2"
    local pool_conf="/etc/php/${php_ver}/fpm/pool.d/${pool_name}.conf"

    echo -e "   [3/8] Configuring sandboxed PHP-FPM pool: ${CYAN}${pool_name}${NC} (Max Workers: ${GREEN}${safe_max_workers}${NC})..."
    mkdir -p "/etc/php/${php_ver}/fpm/pool.d" "/run/php"

    # Pre-create PHP log files owned by tenant so logs_dir can remain non-writable by tenant (Resolves C2)
    touch "${logs_dir}/php_error.log" "${logs_dir}/php_slow.log"
    chown "$vhost_user:www-data" "${logs_dir}/php_error.log" "${logs_dir}/php_slow.log"
    chmod 640 "${logs_dir}/php_error.log" "${logs_dir}/php_slow.log"

    cat > "$pool_conf" <<EOF
; ==============================================================================
; Bashboard Dedicated PHP-FPM Pool: ${domain}
; Multi-Tenancy Architecture: POSIX User Execution, Session Sandbox & open_basedir
; ==============================================================================
[${pool_name}]

user = ${vhost_user}
group = ${vhost_user}

listen = ${dedicated_sock}
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = ${safe_max_workers}
pm.process_idle_timeout = 10s
pm.max_requests = 500

request_terminate_timeout = 120s
catch_workers_output = yes

; Isolated Site Telemetry & Performance SlowLog Engine
php_admin_value[error_log] = ${logs_dir}/php_error.log
php_admin_flag[log_errors] = on
php_admin_flag[expose_php] = off
slowlog = ${logs_dir}/php_slow.log
request_slowlog_timeout = 5s

; Sandboxed Temporary Storage & Session Isolation (Zero Cross-Tenant Leaks)
php_admin_value[upload_tmp_dir] = ${tmp_dir}
php_admin_value[session.save_path] = ${tmp_dir}
php_admin_value[sys_temp_dir] = ${tmp_dir}

; Strict File Access Jail (Eliminating global /tmp/ leakage)
php_admin_value[open_basedir] = /var/www/${domain}/:/dev/urandom:/usr/share/zoneinfo/

; Function Lockdown (Prevents open_basedir bypass via OS shell spawning)
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec,show_source,highlight_file,proc_get_status,posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,posix_setuid

; Realpath Cache Performance Optimization (Neutralizes open_basedir I/O penalty)
php_admin_value[realpath_cache_size] = 4096k
php_admin_value[realpath_cache_ttl] = 600

; Hardened Execution Limits
php_value[memory_limit] = 256M
php_value[upload_max_filesize] = 128M
php_value[post_max_size] = 128M
EOF

    # Validate FPM syntax strictly BEFORE reloading/starting daemon (Resolves W4)
    if ! "/usr/sbin/php-fpm${php_ver}" -t >/dev/null 2>&1; then
        echo -e "   ${RED}❌ [ERROR] PHP-FPM pool syntax validation failed!${NC}" >&2
        "/usr/sbin/php-fpm${php_ver}" -t >&2 || true
        return 1
    fi

    if systemctl is-active --quiet "php${php_ver}-fpm" 2>/dev/null; then
        systemctl reload "php${php_ver}-fpm"
    else
        systemctl enable --now "php${php_ver}-fpm"
    fi

    local retry=0
    while [ ! -S "$dedicated_sock" ] && [ "$retry" -lt 20 ]; do
        sleep 0.1
        retry=$((retry + 1))
    done

    if [ ! -S "$dedicated_sock" ]; then
        echo -e "   ${RED}❌ [ERROR] Dedicated PHP-FPM socket failed to materialize: $dedicated_sock${NC}" >&2
        return 1
    fi
}

configure_isolated_php_pool "$DOMAIN" "$PHP_VER"
php_socket="$dedicated_sock"
rebalance_all_pools

# 8.4 Compile Hardened Nginx Virtual Host Configuration (OWASP & CIS Hardened)
echo -e "   [4/8] Compiling Nginx virtual host configuration..."

rm -f /etc/nginx/sites-enabled/default

# 1. Guarantee Global Rate-Limit Zone Exists
if [ ! -f "/etc/nginx/conf.d/00-bashboard-rate-limit.conf" ]; then
    mkdir -p "/etc/nginx/conf.d"
    printf "%s\n" \
        "# Bashboard Global Security Zone: Mitigates WordPress Login Brute-Force" \
        "limit_req_zone \$binary_remote_addr zone=wplogin:10m rate=10r/m;" \
        "limit_req_status 429;" > "/etc/nginx/conf.d/00-bashboard-rate-limit.conf"
fi

# 2. Guarantee Catch-All Default Server Block (Prevents Unknown Host Header Leaks - Resolves W5)
if [ ! -f "/etc/nginx/conf.d/00-bashboard-default-catchall.conf" ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/catchall.key -out /etc/nginx/ssl/catchall.crt \
        -subj "/CN=invalid.local" 2>/dev/null
    chmod 600 /etc/nginx/ssl/catchall.key
    cat > "/etc/nginx/conf.d/00-bashboard-default-catchall.conf" <<'EOF'
# Bashboard Catch-All Default Server: Drops spoofed/unknown Host headers (444)
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_certificate     /etc/nginx/ssl/catchall.crt;
    ssl_certificate_key /etc/nginx/ssl/catchall.key;
    return 444;
}
EOF
fi

# 3. Guarantee Standard TLS Parameters Snippet Exists
if [ ! -f "/etc/nginx/snippets/ssl-params.conf" ]; then
    mkdir -p "/etc/nginx/snippets"
    cat > "/etc/nginx/snippets/ssl-params.conf" <<'EOF'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384";
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
EOF
fi

http2_mode=$(detect_nginx_http2_mode)
listen_ssl="listen 443 ssl;"
listen_ssl_v6="listen [::]:443 ssl;"
http2_directive=""

if [ "$http2_mode" = "modern" ]; then
    http2_directive="http2 on;"
else
    listen_ssl="listen 443 ssl http2;"
    listen_ssl_v6="listen [::]:443 ssl http2;"
fi

http_server_names="$DOMAIN www.$DOMAIN"
[ "$ENABLE_MEDIA_SUBDOMAIN" -eq 1 ] && http_server_names="$DOMAIN www.$DOMAIN uploads.$DOMAIN"

cat > "$nginx_conf" <<EOF
# HTTP (80) -> ACME Webroot Responder & Canonical HTTPS Redirect
server {
    listen 80;
    listen [::]:80;
    server_name $http_server_names;

    location ^~ /.well-known/acme-challenge/ {
        root $project_root;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 301 https://$DOMAIN\$request_uri;
    }
}

# HTTPS (443) -> Canonical Redirect: www -> non-www
server {
    $listen_ssl
    $listen_ssl_v6
    $http2_directive
    server_name www.$DOMAIN;

    ssl_certificate     $cert_file;
    ssl_certificate_key $key_file;
    include snippets/ssl-params.conf;

    return 301 https://$DOMAIN\$request_uri;
}

# Primary Domain Virtual Host
server {
    $listen_ssl
    $listen_ssl_v6
    $http2_directive
    server_name $DOMAIN;

    root $project_root;
    index index.php index.html;

    ssl_certificate     $cert_file;
    ssl_certificate_key $key_file;
    include snippets/ssl-params.conf;

    access_log $logs_dir/nginx_access.log;
    error_log  $logs_dir/nginx_error.log;

    server_tokens off;
    client_max_body_size 256M;

    # Baseline Security Headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # 1. Protect hidden files (.git, .env, .htaccess) while permitting ACME validation
    location ~ /\.(?!well-known) {
        deny all;
    }

    # 2. Block sensitive project, dependency, lock and configuration files
    location ~* ^/(?:.*/)?(?:wp-config(?:-sample)?\.php|readme\.html|license\.txt|composer\.(?:json|lock)|package(?:-lock)?\.json|yarn\.lock|phpunit\.xml(?:\.dist)?)$ {
        deny all;
    }

    # 3. Block dump, database, backup and log files
    location ~* \.(?:bak|old|orig|save|sql|log|swp)$ {
        deny all;
    }

    # 4. Zero-Trust Media Sandboxing: Completely block script execution in uploads
    location ^~ /wp-content/uploads/ {
        try_files \$uri =404;
        location ~ \.php$ {
            deny all;
        }
    }
    location ^~ /uploads/ {
        try_files \$uri =404;
        location ~ \.php$ {
            deny all;
        }
    }

    # 5. WordPress Core Permalinks Router
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # 6. Block XML-RPC Amplification & Brute-Force Vectors
    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }

    # 7. Login Brute-Force Rate Limiting (Burst: 5, Dedicated Pool Socket)
    location = /wp-login.php {
        limit_req zone=wplogin burst=5 nodelay;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 120s;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }

    # 8. FastCGI PHP Handler (Mapped strictly to Tenant Isolated Pool)
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 120s;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }

    # 9. Static Assets Caching & Disk I/O Optimization
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|avif|woff|woff2)$ {
        expires 30d;
        add_header X-Content-Type-Options "nosniff" always;
        access_log off;
        log_not_found off;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt  { log_not_found off; access_log off; try_files \$uri /index.php?\$args; }
}
EOF

# Append Isolated Media Subdomain block if requested by operator
if [ "$ENABLE_MEDIA_SUBDOMAIN" -eq 1 ]; then
cat >> "$nginx_conf" <<EOF

# Isolated Uploads Media Subdomain Host
server {
    $listen_ssl
    $listen_ssl_v6
    $http2_directive
    server_name uploads.$DOMAIN;

    root $media_root;
    index index.html;

    ssl_certificate     $cert_file;
    ssl_certificate_key $key_file;
    include snippets/ssl-params.conf;

    access_log $logs_dir/uploads_access.log;
    error_log  $logs_dir/uploads_error.log;

    client_max_body_size 256M;

    location ^~ /.well-known/acme-challenge/ {
        root $project_root;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Zero-Trust Policy: Terminate any executable PHP execution attempt
    location ~ \.php$ {
        deny all;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|avif|mp4|pdf)$ {
        expires 365d;
        add_header Access-Control-Allow-Origin "*";
        access_log off;
    }
}
EOF
fi

# Pre-create Nginx log files owned by www-data before Nginx reload (Resolves C2)
touch "$logs_dir/nginx_access.log" "$logs_dir/nginx_error.log"
if [ "$ENABLE_MEDIA_SUBDOMAIN" -eq 1 ]; then
    touch "$logs_dir/uploads_access.log" "$logs_dir/uploads_error.log"
fi
chown www-data:"$vhost_user" "$logs_dir"/*_access.log "$logs_dir"/*_error.log
chmod 640 "$logs_dir"/*_access.log "$logs_dir"/*_error.log

ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/$DOMAIN"

if nginx_test_output=$(nginx -t 2>&1); then
    systemctl reload nginx
    echo -e "   ${GREEN}✅ Nginx Virtual Host validated and reloaded successfully.${NC}"
else
    echo -e "   ${RED}❌ [ERROR] Nginx configuration test failed!${NC}" >&2
    echo -e "${YELLOW}${nginx_test_output}${NC}" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 9. DATABASE PROVISIONING (For WordPress Payload)
# ------------------------------------------------------------------------------
if [ "$PAYLOAD_TYPE" == "wordpress" ]; then
    echo -e "\n   [5/8] Initializing Database & Dedicated Credentials..."

    run_mysql_admin <<EOSQL
CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOSQL
    echo -e "   ${GREEN}✅ Database \`$DB_NAME\` and isolated user \`$DB_USER\` provisioned.${NC}"
fi

# ------------------------------------------------------------------------------
# 10. APPLICATION PAYLOAD DEPLOYMENT & HEADLESS STAGING
# ------------------------------------------------------------------------------
setup_url="https://$DOMAIN/"

if [ "$PAYLOAD_TYPE" == "wordpress" ]; then
    echo -e "\n   [6/8] Staging WordPress Core & Generating Direct Filesystem Config..."

    rm -rf "$tmp_dir/wp-latest.zip" "$tmp_dir/wordpress"
    wget -qO "$tmp_dir/wp-latest.zip" https://wordpress.org/latest.zip
    unzip -q -o "$tmp_dir/wp-latest.zip" -d "$tmp_dir/"

    cp -a "$tmp_dir/wordpress/." "$project_root/"
    rm -rf "$tmp_dir/wp-latest.zip" "$tmp_dir/wordpress"
    mkdir -p "$media_root"

    WP_PHP_BIN="php"
    [[ -x "/usr/bin/php${PHP_VER}" ]] && WP_PHP_BIN="/usr/bin/php${PHP_VER}"

    "$WP_PHP_BIN" /usr/local/bin/wp core config \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASS" \
        --dbhost="localhost" \
        --path="$project_root" \
        --allow-root \
        --skip-plugins \
        --skip-themes \
        --extra-php <<'EOF'
define( 'FS_METHOD', 'direct' );
EOF

    echo -e "   ${GREEN}✅ Headless wp-config.php configured with FS_METHOD=direct.${NC}"
    setup_url="https://$DOMAIN/wp-admin/install.php"
else
    echo -e "\n   [6/8] Creating Blank Site placeholder..."
    cat > "$project_root/index.php" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>$DOMAIN - Site Ready</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; text-align: center; padding: 10% 5%; background: #0f172a; color: #f8fafc; }
        .card { background: #1e293b; border-radius: 12px; padding: 40px; display: inline-block; max-width: 600px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
        h1 { color: #38bdf8; margin-top: 0; }
        p { color: #94a3b8; line-height: 1.6; }
        .badge { background: #0284c7; color: white; padding: 4px 12px; border-radius: 9999px; font-size: 14px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="card">
        <span class="badge">Bashboard VHost Ready</span>
        <h1>$DOMAIN</h1>
        <p>This virtual host is successfully provisioned and serving over HTTPS with an isolated PHP-FPM pool.</p>
        <p><small>Tenant User: ${vhost_user} | Concurrency Ceiling: ${safe_max_workers}</small></p>
    </div>
</body>
</html>
EOF
    echo -e "   ${GREEN}✅ Blank placeholder index.php created.${NC}"
fi

# ------------------------------------------------------------------------------
# 11. ZERO-TRUST POSIX ISOLATION & SYMLINK-SAFE LOGROTATE (Resolves C1 & C2)
# ------------------------------------------------------------------------------
echo -e "   [7/8] Applying Root-Anchored POSIX isolation & Symlink-Safe Logrotate..."

# 1. Root-Anchored Base Directory (root:$vhost_user 750):
#    - Tenant & www-data (in group $vhost_user) can traverse (r-x), Other = --- (Zero cross-tenant access).
#    - Because 'root' owns /var/www/$DOMAIN, the tenant CANNOT unlink state files or rename logs/!
chown "root:$vhost_user" "/var/www/$DOMAIN"
chmod 750 "/var/www/$DOMAIN"

# 2. Web payload owned by tenant: Allows one-click plugin/theme updates directly from WP Dashboard
chown -R "$vhost_user:$vhost_user" "$project_root"
find "$project_root" -type d -exec chmod 755 {} +
find "$project_root" -type f -exec chmod 644 {} +

# 3. wp-config.php restricted to tenant user (600)
if [ -f "$project_root/wp-config.php" ]; then
    chown "$vhost_user:$vhost_user" "$project_root/wp-config.php"
    chmod 600 "$project_root/wp-config.php"
fi

# 4. Logs directory owned by www-data:$vhost_user (750 - Read-Only for tenant, immune to CVE-2016-1247 symlink attacks)
chown "www-data:$vhost_user" "$logs_dir"
chmod 750 "$logs_dir"

# 5. Dedicated Logrotate Drop-in: Nginx logs rotate as www-data; PHP logs rotate via copytruncate
cat > "/etc/logrotate.d/vhost-$DOMAIN" <<EOF
# Bashboard Dedicated Logrotate Policy for $DOMAIN
$logs_dir/*access.log $logs_dir/*error.log {
    su www-data $vhost_user
    daily
    missingok
    rotate 14
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

$logs_dir/php_*.log {
    su $vhost_user www-data
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

# 6. Authoritative Root-Owned State Manifest (Stored strictly in /etc/bashboard/sites/)
cat > "/etc/bashboard/sites/${DOMAIN}.state" <<EOF
DOMAIN=$DOMAIN
TENANT_USER=$vhost_user
POOL_NAME=$pool_name
DB_NAME=$DB_NAME
DB_USER=$DB_USER
PHP_VER=$PHP_VER
CREATED_AT=$(date -u +%s)
EOF
chown root:root "/etc/bashboard/sites/${DOMAIN}.state"
chmod 600 "/etc/bashboard/sites/${DOMAIN}.state"
rm -f "/var/www/$DOMAIN/.bashboard-state" 2>/dev/null || true

# 7. Deploy Global 'domain' CLI Helper & Bash Completion for Administrative Tenant Shell Access
cat > "/usr/local/bin/domain" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dom="${1:-}"
if [[ -z "$dom" ]]; then
    echo "Available isolated virtual hosts:"
    sudo find /var/www -mindepth 1 -maxdepth 1 -type d ! -name "html" -printf "  - %f\n" 2>/dev/null | sort
    echo "Usage: domain <domain.com>"
    exit 1
fi
if ! sudo test -d "/var/www/$dom/public_html"; then
    echo "❌ Error: Virtual host '/var/www/$dom/public_html' not found!" >&2
    exit 1
fi
vuser=$(sudo stat -c '%U' "/var/www/$dom/public_html")
echo -e "\033[1;36m>>> Entering isolated shell for \033[1;33m$dom\033[1;36m (Tenant: \033[1;32m$vuser\033[1;36m) — Type 'exit' to return <<<\033[0m"
exec sudo -u "$vuser" -- env HOME="/var/www/$dom" bash -c "cd '/var/www/$dom/public_html' && exec /bin/bash"
EOF
chmod 755 "/usr/local/bin/domain"

if [ -d "/etc/bash_completion.d" ]; then
    cat > "/etc/bash_completion.d/bashboard-domain" <<'EOF'
_bashboard_domain_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local sites=""
    if [ -d /etc/nginx/sites-available ]; then
        sites=$(find /etc/nginx/sites-available -maxdepth 1 -type f ! -name "default" -printf "%f " 2>/dev/null)
    fi
    COMPREPLY=( $(compgen -W "$sites" -- "$cur") )
}
complete -F _bashboard_domain_complete domain
EOF
fi

# ------------------------------------------------------------------------------
# 12. LET'S ENCRYPT AUTOMATION ENGINE (Interface-First IP & Graceful Subdomains)
# ------------------------------------------------------------------------------
resolve_public_ip() {
    local target_d="$1"
    local ip=""

    if command -v dig >/dev/null 2>&1; then
        for ns in 1.1.1.1 8.8.8.8 9.9.9.9; do
            ip=$(dig +short +time=2 +tries=1 @"$ns" "$target_d" A 2>/dev/null \
                | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
            if [[ -n "$ip" ]]; then
                echo "$ip"
                return 0
            fi
        done
    fi

    for doh_endpoint in \
        "https://1.1.1.1/dns-query?name=${target_d}&type=A" \
        "https://8.8.8.8/resolve?name=${target_d}&type=A"; do
        ip=$(curl -4 -s --connect-timeout 3 -m 4 -H "accept: application/dns-json" "$doh_endpoint" 2>/dev/null \
            | grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' \
            | tail -n1 | cut -d'"' -f4 || true)
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    if command -v host >/dev/null 2>&1; then
        for ns in 1.1.1.1 8.8.8.8; do
            ip=$(host -t A -W 2 "$target_d" "$ns" 2>/dev/null \
                | awk '/has address/ {print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
            if [[ -n "$ip" ]]; then
                echo "$ip"
                return 0
            fi
        done
    fi

    echo ""
}

get_server_public_ips() {
    local ips=()
    local nic_ip cached_ip ext_ip

    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r nic_ip; do
            [[ -n "$nic_ip" ]] && ips+=("$nic_ip")
        done < <(ip -4 addr show scope global 2>/dev/null \
            | awk '/inet / {split($2, a, "/"); print a[1]}' \
            | grep -vE '^(10\.|127\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.)' || true)
    fi

    if [ -f "/run/bashboard_ip" ]; then
        cached_ip=$(cat "/run/bashboard_ip" 2>/dev/null | tr -d '[:space:]' || true)
        [[ "$cached_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ips+=("$cached_ip")
    fi

    if [ ${#ips[@]} -eq 0 ]; then
        for ip_url in "https://api.ipify.org" "https://icanhazip.com" "https://ifconfig.me/ip"; do
            ext_ip=$(curl -4 -s --noproxy '*' --connect-timeout 3 -m 4 "$ip_url" 2>/dev/null | tr -d '[:space:]' || true)
            if [[ "$ext_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ips+=("$ext_ip")
                break
            fi
        done
    fi

    if [ ${#ips[@]} -gt 0 ]; then
        printf "%s\n" "${ips[@]}" | awk '!seen[$0]++'
    fi
}

issue_letsencrypt_ssl() {
    local domain="$1"
    local enable_media="${2:-0}"

    echo -e "\n   [8/8] Automated Let's Encrypt TLS Engine..."

    if ! command -v certbot >/dev/null 2>&1; then
        echo -e "         Installing Certbot ACME client..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get -o DPkg::Lock::Timeout=60 update -qq && apt-get -o DPkg::Lock::Timeout=60 install -y -qq certbot python3-certbot-nginx
    fi

    local server_ips=()
    while IFS= read -r sip; do
        [[ -n "$sip" ]] && server_ips+=("$sip")
    done < <(get_server_public_ips)

    local primary_server_ip="${server_ips[0]:-Unknown}"

    echo -e "         Executing pre-flight DNS verification against public nameservers..."
    local candidate_domains=("$domain" "www.$domain")
    [[ "$enable_media" -eq 1 ]] && candidate_domains+=("uploads.$domain")

    local verified_domains=()

    for d in "${candidate_domains[@]}"; do
        local resolved_ip match_found=0
        resolved_ip=$(resolve_public_ip "$d")

        if [[ -n "$resolved_ip" ]] && [ ${#server_ips[@]} -gt 0 ]; then
            for sip in "${server_ips[@]}"; do
                if [[ "$resolved_ip" == "$sip" ]]; then
                    match_found=1
                    break
                fi
            done
        fi

        if [ "$match_found" -eq 1 ]; then
            verified_domains+=("$d")
        else
            if [[ "$d" == "$domain" ]]; then
                echo -e "         ${YELLOW}⚠️  DNS pre-flight check bypassed for primary domain '$d':${NC}"
                echo -e "            Domain points to : ${RED}${resolved_ip:-Unresolved}${NC}"
                echo -e "            Server Public IP : ${GREEN}${primary_server_ip}${NC}"
                echo -e "         ${YELLOW}Skipping Let's Encrypt request to avoid Rate-Limit lockouts.${NC}"
                echo -e "         ${GRAY}Self-signed fallback certificate remains active.${NC}"
                return 0
            else
                echo -e "         ${YELLOW}ℹ️  Subdomain '$d' DNS is ${RED}${resolved_ip:-Unresolved}${YELLOW} (expected ${GREEN}${primary_server_ip}${YELLOW}). Excluding '$d' from cert request.${NC}"
            fi
        fi
    done

    local domain_args=()
    for d in "${verified_domains[@]}"; do
        domain_args+=("-d" "$d")
    done

    mkdir -p "$project_root/.well-known/acme-challenge"
    chown -R "$vhost_user:$vhost_user" "$project_root/.well-known"
    chmod -R 755 "$project_root/.well-known"

    echo -e "         DNS verified for [${verified_domains[*]}]! Requesting official TLS certificate..."
    if certbot certonly --webroot -w "$project_root" \
        --cert-name "$domain" \
        --non-interactive --agree-tos \
        --register-unsafely-without-email \
        --keep-until-expiring \
        "${domain_args[@]}" >> /var/log/bashboard_ssl.log 2>&1; then

        local le_fullchain="/etc/letsencrypt/live/${domain}/fullchain.pem"
        local le_privkey="/etc/letsencrypt/live/${domain}/privkey.pem"

        if [[ -f "$le_fullchain" && -f "$le_privkey" ]]; then
            sed -i "s|ssl_certificate[[:space:]]\+$cert_file;|ssl_certificate     $le_fullchain;|g" "$nginx_conf"
            sed -i "s|ssl_certificate_key[[:space:]]\+$key_file;|ssl_certificate_key $le_privkey;|g" "$nginx_conf"

            if nginx -t >/dev/null 2>&1; then
                systemctl reload nginx
                rm -f "$cert_file" "$key_file"
                echo -e "         ${GREEN}✅ Let's Encrypt certificate cleanly bound for: ${verified_domains[*]}${NC}"
            else
                sed -i "s|ssl_certificate[[:space:]]\+$le_fullchain;|ssl_certificate     $cert_file;|g" "$nginx_conf"
                sed -i "s|ssl_certificate_key[[:space:]]\+$le_privkey;|ssl_certificate_key $key_file;|g" "$nginx_conf"
                echo -e "         ${RED}❌ Nginx reload failed with new cert; reverted to self-signed fallback.${NC}"
            fi
        fi

        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat > /etc/letsencrypt/renewal-hooks/deploy/bashboard-nginx-reload.sh <<'EOF'
#!/usr/bin/env bash
nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true
EOF
        chmod 755 /etc/letsencrypt/renewal-hooks/deploy/bashboard-nginx-reload.sh
        systemctl enable --now certbot.timer >/dev/null 2>&1 || true
    else
        echo -e "         ${RED}❌ Certbot issuance failed! Check /var/log/bashboard_ssl.log for details.${NC}"
        echo -e "         ${GRAY}Self-signed fallback certificate remains active.${NC}"
    fi
}

if [ "$ENABLE_LETSENCRYPT" -eq 1 ]; then
    issue_letsencrypt_ssl "$DOMAIN" "$ENABLE_MEDIA_SUBDOMAIN" || true
fi

# ------------------------------------------------------------------------------
# 12.5 UNIVERSAL LOCAL LOOPBACK PINNING (/etc/hosts)
# ------------------------------------------------------------------------------
extra_hosts_entries=""
[ "$ENABLE_MEDIA_SUBDOMAIN" -eq 1 ] && extra_hosts_entries="uploads.$DOMAIN"

if ! grep -qE "[[:space:]]${DOMAIN}([[:space:]]|$)" /etc/hosts; then
    echo "127.0.0.1 $DOMAIN www.$DOMAIN ${extra_hosts_entries}" >> /etc/hosts
    echo -e "   ${GREEN}✅ Local Loopback Pinned: 127.0.0.1 mapped to ${DOMAIN} (/etc/hosts).${NC}"
fi

trap - ERR

# ------------------------------------------------------------------------------
# 13. FINAL DEPLOYMENT SUMMARY REPORT
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}=================================================================="
echo -e "   🎉 Virtual Host & Environment Provisioned Successfully!"
echo -e "==================================================================${NC}"
echo -e "Primary Domain:        ${YELLOW}https://$DOMAIN${NC}"
echo -e "Canonical Redirect:    ${WHITE}https://www.$DOMAIN -> https://$DOMAIN (301)${NC}"
[[ "$ENABLE_MEDIA_SUBDOMAIN" -eq 1 ]] && echo -e "Uploads Subdomain:     ${YELLOW}https://uploads.$DOMAIN${NC} (Root: ${WHITE}$media_root${NC})"
echo -e "Payload Architecture:  ${WHITE}$( [ "$PAYLOAD_TYPE" == "wordpress" ] && echo "Standard WordPress" || echo "Blank Site" )${NC}"
echo -e "Isolated Tenant User:  ${CYAN}${vhost_user}${NC} (Root-Anchored Parent 750 / C1 & C2 Immune)"
echo -e "Enter Tenant Shell:    ${YELLOW}domain $DOMAIN${NC}"
echo -e "Temp & Session Sandbox:${WHITE}$tmp_dir${NC} ${GREEN}(chmod 700 / sys_temp_dir)${NC}"
echo -e "PHP-FPM Worker Ceiling:${WHITE}${safe_max_workers} Workers${NC} ${GREEN}(Rebalanced & Function Locked)${NC}"
echo -e "Security Hardening:    ${GREEN}Brute-Force Rate Limiting Active (/wp-login.php)${NC}"
echo -e "Dedicated Logrotate:   ${WHITE}/etc/logrotate.d/vhost-$DOMAIN${NC} ${GREEN}(CVE-2016-1247 Safe)${NC}"
echo -e "Web Setup Entrypoint:  ${CYAN}$setup_url${NC}"

if [ "$PAYLOAD_TYPE" == "wordpress" ]; then
    echo -e "------------------------------------------------------------------"
    echo -e "Database Details (Configured automatically via CLI):"
    echo -e "  - DB Name:           ${YELLOW}$DB_NAME${NC}"
    echo -e "  - DB User:           ${YELLOW}$DB_USER${NC}"
    echo -e "  - DB Password:       ${YELLOW}$DB_PASS${NC}"
    echo -e "  - DB Host:           ${YELLOW}localhost${NC}"
fi

echo -e "------------------------------------------------------------------"
echo -e "Logs & Diagnostic Paths:"
echo -e "  - Slow Queries:      ${WHITE}$logs_dir/php_slow.log${NC}"
echo -e "  - PHP Error Stream:  ${WHITE}$logs_dir/php_error.log${NC}"
echo -e "  - Nginx Access Stream:${WHITE}$logs_dir/nginx_access.log${NC}"
echo -e "  - Nginx Error Stream: ${WHITE}$logs_dir/nginx_error.log${NC}"
echo -e "${GREEN}==================================================================${NC}"
exit 0