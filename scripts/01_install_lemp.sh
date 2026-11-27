#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD MODULE: [01] Enterprise LEMP Stack Interactive TUI Installer
# Version:          1.9.1 (Security Audit Hardened: Strict Subshell run_task,
#                   SHA-512 Verified WP-CLI, Fixed phpMyAdmin Location Order,
#                   SHA-256 Hashed Redis ACLs + Explicit Loopback Bind,
#                   CIDR-Guarded Cloudflare Updater, Shared Root ACME Webroot)
# Architecture:     Interactive TUI | Dynamic Discovery | Global Infrastructure Base
# Platform:         Debian 11/12/13, Ubuntu 22.04/24.04/26.04 LTS
# ==============================================================================
set -Eeuo pipefail

ESC=$(printf '\033')
B_O=$(printf '\133')
B_C=$(printf '\135')

# ------------------------------------------------------------------------------
# 1. TERMINAL PALETTE & ABSOLUTE COLUMN ALIGNMENT
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
# 2. PRIVILEGE, OS DETECTION & SECURE LOGGING ASSERTION
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ [FATAL] This module must be executed as root.${NC}" >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo -e "${RED}❌ [FATAL] This installer strictly requires a Debian or Ubuntu distribution.${NC}" >&2
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-ubuntu}"
    OS_CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || true)}"
else
    echo -e "${RED}❌ [FATAL] /etc/os-release not found. Cannot determine Linux distribution.${NC}" >&2
    exit 1
fi

readonly INSTALL_LOG="/var/log/bashboard_lemp_install.log"
if [ -L "$INSTALL_LOG" ]; then
    echo -e "${RED}❌ [FATAL] Security Alert: Install log path is a symlink! Aborting.${NC}" >&2
    exit 1
fi
(
    umask 077
    touch "$INSTALL_LOG"
    chmod 600 "$INSTALL_LOG"
) 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. DYNAMIC PHP SOCKET & FILESYSTEM AUTODISCOVERY
# ------------------------------------------------------------------------------
detect_installed_phps() {
    local phps=()

    shopt -s nullglob
    local socks=( /run/php/php*-fpm.sock /var/run/php/php*-fpm.sock )
    shopt -u nullglob

    local sock ver
    for sock in "${socks[@]}"; do
        if [ -S "$sock" ]; then
            ver=$(basename "$sock" | grep -oE '[0-9]+\.[0-9]+' || true)
            [[ -n "$ver" ]] && phps+=("$ver")
        fi
    done

    if [ -d "/etc/php" ]; then
        local d b
        for d in /etc/php/*; do
            if [ -d "$d" ]; then
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

SYSTEM_PHPS=$(detect_installed_phps)
LATEST_DETECTED_PHP=$(echo "$SYSTEM_PHPS" | awk -F',' '{print $NF}' | tr -d '[:space:]')
PHP_VER="${LATEST_DETECTED_PHP:-8.3}"

# Default component toggle states
INSTALL_NGINX=1
INSTALL_MARIADB=1
INSTALL_PHP=1
INSTALL_REDIS=1
INSTALL_WPCLI=1
INSTALL_PMA=1
DB_ROOT_PASS=""

# ------------------------------------------------------------------------------
# 4. TUI STATUS INDICATORS & HELPERS
# ------------------------------------------------------------------------------
detect_installed() {
    local target="$1"
    if [[ "$target" == /* ]]; then
        if [ -d "$target" ] || [ -f "$target" ]; then
            echo -e "${GREEN}● INSTALLED${NC}"
        else
            echo -e "${GRAY}○ NOT INSTALLED${NC}"
        fi
    else
        if command -v "$target" >/dev/null 2>&1; then
            echo -e "${GREEN}● INSTALLED${NC}"
        else
            echo -e "${GRAY}○ NOT INSTALLED${NC}"
        fi
    fi
}

detect_pma_status() {
    if [ -d "/usr/share/phpmyadmin" ]; then
        if [ -f "/etc/nginx/conf.d/00-bashboard-phpmyadmin.conf" ]; then
            echo -e "${GREEN}● INSTALLED (127.0.0.1:8080)${NC}"
        else
            echo -e "${YELLOW}● INSTALLED (Unconfigured)${NC}"
        fi
    else
        echo -e "${GRAY}○ NOT INSTALLED${NC}"
    fi
}

detect_php_status() {
    if [ -n "$SYSTEM_PHPS" ]; then
        if [[ ",$SYSTEM_PHPS," == *",$PHP_VER,"* ]]; then
            echo -e "${GREEN}● INSTALLED (v${PHP_VER})${NC}"
        else
            echo -e "${YELLOW}● OTHER (v${SYSTEM_PHPS})${NC}"
        fi
    else
        echo -e "${GRAY}○ NOT INSTALLED${NC}"
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

apt_pkg_available() {
    local pkg="$1"
    local cand
    cand=$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}' || true)
    [[ -n "$cand" && "$cand" != "(none)" ]]
}

# Zero-Leak MariaDB root query runner (never exposes password in /proc argv)
run_mariadb_root() {
    local db_bin="mariadb"
    command -v mariadb >/dev/null 2>&1 || db_bin="mysql"

    if "$db_bin" -u root -e "SELECT 1;" >/dev/null 2>&1; then
        "$db_bin" -u root "$@"
    elif [ -n "$DB_ROOT_PASS" ]; then
        MYSQL_PWD="$DB_ROOT_PASS" "$db_bin" -u root "$@"
    else
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 5. TUI DASHBOARD RENDERER
# ------------------------------------------------------------------------------
draw_tui() {
    clear
    local st_nginx st_mariadb st_php st_redis st_wpcli st_pma
    st_nginx=$(detect_installed nginx)
    st_mariadb=$(detect_installed mariadb)
    [[ "$st_mariadb" == *"NOT INSTALLED"* ]] && st_mariadb=$(detect_installed mysql)
    st_php=$(detect_php_status)
    st_redis=$(detect_installed redis-server)
    st_wpcli=$(detect_installed wp)
    st_pma=$(detect_pma_status)

    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Module: %-25s${NC}\n" "BASHBOARD LEMP SUITE (V1.9.1)" "LEMP Installer TUI"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   📋 ${PURPLE}${BOLD}COMPONENT SELECTION & ENVIRONMENT STATUS${NC}"
    echo -e "      Target Distribution: ${WHITE}${NAME:-Linux} (${OS_CODENAME})${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    printf "   ${CYAN}[1]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_NGINX")" "Nginx Web Server" "$st_nginx"
    printf "   ${CYAN}[2]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_MARIADB")" "MariaDB SQL Server" "$st_mariadb"
    printf "   ${CYAN}[3]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_PHP")" "PHP-FPM Engine" "$st_php"
    printf "   ${CYAN}[4]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_REDIS")" "Redis Cache (ACL)" "$st_redis"
    printf "   ${CYAN}[5]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_WPCLI")" "WP-CLI (SHA-512)" "$st_wpcli"
    printf "   ${CYAN}[6]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_PMA")" "phpMyAdmin (Tunnel)" "$st_pma"

    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ⚙️  ${PURPLE}${BOLD}STACK TUNING PARAMETERS${NC}"
    printf "      %-22s: ${YELLOW}%-22s${NC}${COL_MID}${GRAY}│${NC} Change with: ${CYAN}[7]${NC}\n" "Target PHP Version" "v${PHP_VER} $([[ ",$SYSTEM_PHPS," == *",$PHP_VER,"* ]] && echo "(Installed)")"

    local db_pass_disp="Auto-Socket (Native)"
    if [ -n "$DB_ROOT_PASS" ]; then db_pass_disp="Dual (Socket + Pass)"; fi
    printf "      %-22s: ${YELLOW}%-22s${NC}${COL_MID}${GRAY}│${NC} Change with: ${CYAN}[8]${NC}\n" "MariaDB Root Pass" "$db_pass_disp"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    echo -e "   ${GREEN}${BOLD}[9] ⚡ START COMPONENT INSTALLATION${NC}"
    echo -e "   ${RED}${BOLD}[0] ↩️  CANCEL AND RETURN TO BASHBOARD${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# ------------------------------------------------------------------------------
# 6. INTERACTIVE MENU EVENT LOOP
# ------------------------------------------------------------------------------
while true; do
    draw_tui
    tput cnorm 2>/dev/null || true
    echo -ne "\n   ${BOLD}${WHITE}Toggle or Choose Action [0-9]:${NC} "
    read -r opt || opt="0"

    case "$opt" in
        1) INSTALL_NGINX=$(( 1 - INSTALL_NGINX )) ;;
        2) INSTALL_MARIADB=$(( 1 - INSTALL_MARIADB )) ;;
        3) INSTALL_PHP=$(( 1 - INSTALL_PHP )) ;;
        4) INSTALL_REDIS=$(( 1 - INSTALL_REDIS )) ;;
        5) INSTALL_WPCLI=$(( 1 - INSTALL_WPCLI )) ;;
        6) INSTALL_PMA=$(( 1 - INSTALL_PMA )) ;;
        7)
            echo -e "\n   ${CYAN}Detected on Server:${NC} ${SYSTEM_PHPS:-None}"
            read -rp "   Enter Target PHP Version (e.g. 7.4, 8.1, 8.2, 8.3, 8.4, 8.5): " user_php
            user_php=$(echo "$user_php" | tr -d '[:space:]')
            if [[ "$user_php" =~ ^[789]\.[0-9]+$ ]]; then
                PHP_VER="$user_php"
            else
                echo -e "   ${RED}Invalid PHP syntax (expected: X.Y). Keeping ${PHP_VER}.${NC}"
                sleep 1.2
            fi
            ;;
        8)
            echo ""
            read -rsp "   Set MariaDB Root Password (leave blank for unix_socket only): " user_db_pass
            echo ""
            DB_ROOT_PASS="$user_db_pass"
            ;;
        9)
            if [ "$INSTALL_NGINX" -eq 0 ] && [ "$INSTALL_MARIADB" -eq 0 ] && [ "$INSTALL_PHP" -eq 0 ] && [ "$INSTALL_REDIS" -eq 0 ] && [ "$INSTALL_WPCLI" -eq 0 ] && [ "$INSTALL_PMA" -eq 0 ]; then
                echo -e "\n   ${YELLOW}No components selected! Please toggle at least one.${NC}"
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
# 7. PROVISIONING ENGINE & STRICT-MODE STRUCTURED TASK LOGGER
# ==============================================================================
clear
echo -e "${CYAN}==================================================================${NC}"
echo -e "   🚀 ${BOLD}${WHITE}Executing Production LEMP Stack Provisioning...${NC}"
echo -e "   📄 Detailed Log File: ${YELLOW}${INSTALL_LOG}${NC}"
echo -e "${CYAN}==================================================================${NC}\n"

export DEBIAN_FRONTEND=noninteractive

apt-get() {
    command apt-get -o DPkg::Lock::Timeout=60 "$@"
}

# Executes task inside an independent strict subshell so 'set -e' is NEVER neutralized by 'if "$@"'
run_task() {
    local task_name="$1"
    shift
    printf "   %-55s ... " "$task_name"
    echo -e "\n--- [$(date '+%Y-%m-%d %H:%M:%S')] TASK: $task_name ---" >> "$INSTALL_LOG"

    local rc=0
    set +e
    (
        set -Eeuo pipefail
        "$@"
    ) >> "$INSTALL_LOG" 2>&1
    rc=$?
    set -e

    if [ "$rc" -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC}"
        return 0
    else
        echo -e "${RED}[FAILED]${NC}"
        echo -e "\n${RED}Task failed! Inspect error log with:${NC} tail -n 40 $INSTALL_LOG" >&2
        return "$rc"
    fi
}

mkdir -p -m 0700 /etc/bashboard /etc/bashboard/sites

run_task "Updating APT package index" apt-get update -y
run_task "Installing base build & DNS utilities" apt-get install -y --no-install-recommends \
    software-properties-common curl wget gnupg2 ca-certificates lsb-release ufw unzip dnsutils debconf-utils openssl

# ------------------------------------------------------------------------------
# 8. COMPONENT 1: NGINX WEBSERVER, SHARED ROOT ACME WEBROOT & CLOUDFLARE REAL-IP
# ------------------------------------------------------------------------------
if [ "$INSTALL_NGINX" -eq 1 ]; then
    echo -e "\n${BLUE}--- [1/6] Configuring Nginx Web Server & Global Primitives ---${NC}"
    run_task "Installing Nginx package" apt-get install -y nginx
    run_task "Enabling and starting Nginx daemon" systemctl enable --now nginx

    mkdir -p /etc/nginx/snippets /etc/nginx/ssl /etc/nginx/conf.d
    # Shared root-owned ACME webroot eliminates Certbot root-writes inside tenant directories
    mkdir -p /var/www/_acme-challenge/.well-known/acme-challenge
    chown -R root:root /var/www/_acme-challenge
    chmod 755 /var/www/_acme-challenge /var/www/_acme-challenge/.well-known /var/www/_acme-challenge/.well-known/acme-challenge

    # Remove default stock symlink to prevent Certbot parser collisions
    rm -f /etc/nginx/sites-enabled/default

    # 8.1 Standard FastCGI snippet
    if [ ! -f "/etc/nginx/snippets/fastcgi-php.conf" ]; then
        cat > "/etc/nginx/snippets/fastcgi-php.conf" <<'EOF'
fastcgi_split_path_info ^(.+\.php)(/.+)$;
try_files $fastcgi_script_name =404;
set $path_info $fastcgi_path_info;
fastcgi_param PATH_INFO $path_info;
fastcgi_index index.php;
include fastcgi_params;
EOF
    fi

    # 8.2 Standard modern TLS parameters
    if [ ! -f "/etc/nginx/snippets/ssl-params.conf" ]; then
        cat > "/etc/nginx/snippets/ssl-params.conf" <<'EOF'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384";
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
EOF
    fi

    # 8.3 Global Cloudflare Real-IP Engine (Preserves live updates & blocks 0.0.0.0/0 CIDRs)
    deploy_cf_realip() {
        local cf_conf="/etc/nginx/conf.d/00-cloudflare-realip.conf"

        # Only seed fallback list if config doesn't already exist (avoids overwriting freshly synced ranges)
        if [ ! -s "$cf_conf" ]; then
            cat > "$cf_conf" <<'EOF'
# Cloudflare Official IP Ranges (Restores Real Visitor IP)
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;

real_ip_header CF-Connecting-IP;
real_ip_recursive on;
EOF
        fi

        cat > "/usr/local/bin/bashboard-update-cf-ips" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CF_CONF="/etc/nginx/conf.d/00-cloudflare-realip.conf"
TMP_CONF=$(mktemp /run/cf_realip_XXXXXX.conf)
trap 'rm -f "$TMP_CONF"' EXIT

v4=$(curl -fsSL --connect-timeout 5 --max-time 10 https://www.cloudflare.com/ips-v4)
v6=$(curl -fsSL --connect-timeout 5 --max-time 10 https://www.cloudflare.com/ips-v6)

# Strict CIDR validation: rejects wildcard/overbroad masks (e.g., 0.0.0.0/0../7 or ::/0../15)
v4_clean=$(echo "$v4" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}/([89]|[12][0-9]|3[0-2])$' | grep -vE '^(0\.|10\.|127\.|169\.254\.|192\.168\.)' || true)
v6_clean=$(echo "$v6" | grep -E '^[0-9a-fA-F:]+/(1[6-9]|[2-9][0-9]|1[01][0-9]|12[0-8])$' | grep -vE '^::/' || true)

v4_cnt=$(echo "$v4_clean" | grep -c '/' || true)
v6_cnt=$(echo "$v6_clean" | grep -c '/' || true)
[ "$v4_cnt" -ge 8 ] && [ "$v6_cnt" -ge 4 ] || exit 1

{
    echo "# Cloudflare Official IP Ranges (Auto-Updated: $(date -u '+%Y-%m-%d'))"
    echo "$v4_clean" | sed 's|^|set_real_ip_from |; s|$|;|'
    echo "$v6_clean" | sed 's|^|set_real_ip_from |; s|$|;|'
    echo ""
    echo "real_ip_header CF-Connecting-IP;"
    echo "real_ip_recursive on;"
} > "$TMP_CONF"

cp "$CF_CONF" "${CF_CONF}.bak" 2>/dev/null || true
chmod 644 "$TMP_CONF"
mv -f "$TMP_CONF" "$CF_CONF"
if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx >/dev/null 2>&1 || true
    rm -f "${CF_CONF}.bak"
else
    mv -f "${CF_CONF}.bak" "$CF_CONF" 2>/dev/null || true
    exit 1
fi
EOF
        chmod 755 "/usr/local/bin/bashboard-update-cf-ips"

        cat > "/etc/cron.d/bashboard-cf-ips" <<'EOF'
# Bashboard Monthly Cloudflare Real-IP Range Synchronizer
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 4 1 * * root /usr/local/bin/bashboard-update-cf-ips >/dev/null 2>&1 || true
EOF
        chmod 644 "/etc/cron.d/bashboard-cf-ips"

        # Best-effort live sync on install (keeps seeded fallback if offline)
        /usr/local/bin/bashboard-update-cf-ips || true
    }
    run_task "Configuring Cloudflare Real-IP & CIDR-guarded updater" deploy_cf_realip

    # 8.4 Global Rate-Limit Zone (Rate: 10r/m, Status: 429)
    run_task "Deploying Global Login Rate-Limit Zone" bash -c '
        rl_conf="/etc/nginx/conf.d/00-bashboard-rate-limit.conf"
        printf "%s\n" \
            "# Bashboard Global Security Zone: Mitigates Login Brute-Force" \
            "limit_req_zone \$binary_remote_addr zone=wplogin:10m rate=10r/m;" \
            "limit_req_status 429;" > "$rl_conf"
    '

    run_task "Validating Nginx configuration syntax" nginx -t
    systemctl reload nginx >> "$INSTALL_LOG" 2>&1 || true

    if command -v ufw >/dev/null 2>&1; then
        ufw allow 80/tcp comment "HTTP Web Ingress" >> "$INSTALL_LOG" 2>&1 || true
        ufw allow 443/tcp comment "HTTPS Web Ingress" >> "$INSTALL_LOG" 2>&1 || true
    fi
fi

# ------------------------------------------------------------------------------
# 9. COMPONENT 2: MARIADB DATABASE ENGINE (Zero /proc Leak Stdin Auth)
# ------------------------------------------------------------------------------
if [ "$INSTALL_MARIADB" -eq 1 ]; then
    echo -e "\n${BLUE}--- [2/6] Configuring MariaDB Database Server ---${NC}"
    run_task "Installing MariaDB Server & Client" apt-get install -y mariadb-server mariadb-client
    run_task "Enabling and starting MariaDB daemon" systemctl enable --now mariadb

    secure_mariadb_baseline() {
        run_mariadb_root <<'EOSQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOSQL
    }
    run_task "Hardening MariaDB baseline (removing anonymous/test)" secure_mariadb_baseline

    if [ -n "$DB_ROOT_PASS" ]; then
        apply_mariadb_root_pass() {
            local esc_pass="${DB_ROOT_PASS//\\/\\\\}"
            esc_pass="${esc_pass//\'/\'\'}"
            run_mariadb_root <<EOSQL
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('${esc_pass}');
FLUSH PRIVILEGES;
EOSQL
        }
        run_task "Setting MariaDB root credentials (preserving unix_socket)" apply_mariadb_root_pass
    else
        echo -e "   ${GRAY}MariaDB root left with native unix_socket authentication (Secure).${NC}"
    fi
fi

# ------------------------------------------------------------------------------
# 10. COMPONENT 3: PHP-FPM POOL, EXTENSIONS & IMAGEMAGICK HARDENING
# ------------------------------------------------------------------------------
if [ "$INSTALL_PHP" -eq 1 ]; then
    echo -e "\n${BLUE}--- [3/6] Configuring PHP ${PHP_VER}-FPM Engine & Modules ---${NC}"

    if ! apt_pkg_available "php${PHP_VER}-fpm"; then
        if [ "$OS_ID" = "ubuntu" ]; then
            if ! grep -rq "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
                run_task "Adding Ondrej PHP PPA for Ubuntu" add-apt-repository -y ppa:ondrej/php
                run_task "Refreshing APT cache for Ubuntu PPA" apt-get update -y
            fi
        elif [ "$OS_ID" = "debian" ]; then
            if [ ! -f "/etc/apt/sources.list.d/sury-php.list" ]; then
                run_task "Registering Sury PHP Keyring for Debian (${OS_CODENAME})" bash -c '
                    mkdir -p -m 0755 /etc/apt/keyrings
                    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/sury-php.gpg
                    echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ '"${OS_CODENAME}"' main" > /etc/apt/sources.list.d/sury-php.list
                '
                run_task "Refreshing APT cache for Debian Sury" apt-get update -y
            fi
        fi
    fi

    PHP_CANDIDATE_MODULES=(
        "php${PHP_VER}-fpm"
        "php${PHP_VER}-cli"
        "php${PHP_VER}-common"
        "php${PHP_VER}-mysql"
        "php${PHP_VER}-curl"
        "php${PHP_VER}-gd"
        "php${PHP_VER}-intl"
        "php${PHP_VER}-mbstring"
        "php${PHP_VER}-soap"
        "php${PHP_VER}-xml"
        "php${PHP_VER}-zip"
        "php${PHP_VER}-bcmath"
        "php${PHP_VER}-opcache"
        "php${PHP_VER}-readline"
        "php${PHP_VER}-redis"
        "php${PHP_VER}-imagick"
    )

    VALID_PHP_PKGS=()
    for pkg in "${PHP_CANDIDATE_MODULES[@]}"; do
        if apt_pkg_available "$pkg"; then
            VALID_PHP_PKGS+=("$pkg")
        else
            ext_name="${pkg#php${PHP_VER}-}"
            if apt_pkg_available "php-${ext_name}"; then
                VALID_PHP_PKGS+=("php-${ext_name}")
            else
                echo "   [INFO] Skipping unavailable/built-in package: $pkg" >> "$INSTALL_LOG"
            fi
        fi
    done

    if [ ${#VALID_PHP_PKGS[@]} -eq 0 ]; then
        echo -e "   ${RED}❌ [ERROR] No installable packages found for PHP ${PHP_VER} in APT repositories.${NC}" >&2
        exit 1
    fi

    run_task "Installing PHP ${PHP_VER}-FPM core & available extensions" \
        apt-get install -y "${VALID_PHP_PKGS[@]}"

    php_ini_file="/etc/php/${PHP_VER}/fpm/php.ini"
    if [ -f "$php_ini_file" ]; then
        run_task "Tuning PHP-FPM php.ini limits & hiding expose_php" bash -c "
            sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 128M/' '$php_ini_file'
            sed -i 's/^post_max_size = .*/post_max_size = 128M/' '$php_ini_file'
            sed -i 's/^memory_limit = .*/memory_limit = 512M/' '$php_ini_file'
            sed -i 's/^max_execution_time = .*/max_execution_time = 300/' '$php_ini_file'
            sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' '$php_ini_file'
            sed -i 's/^expose_php = .*/expose_php = Off/' '$php_ini_file'
        "
    fi

    # Harden ImageMagick policy.xml to block Ghostscript/URL/MVG delegate exploits
    harden_imagemagick_policy() {
        shopt -s nullglob
        local policies=( /etc/ImageMagick-*/policy.xml )
        shopt -u nullglob
        local pol coder
        for pol in "${policies[@]}"; do
            [ -f "$pol" ] || continue
            sed -i '/<!-- Bashboard ImageMagick Security -->/,/<!-- End Bashboard ImageMagick Security -->/d' "$pol"
            local rules="<!-- Bashboard ImageMagick Security -->"
            for coder in EPHEMERAL URL HTTPS HTTP FTP MVG MSL TEXT LABEL PS EPS PDF XPS; do
                rules="${rules}\n  <policy domain=\"coder\" rights=\"none\" pattern=\"${coder}\" />"
            done
            rules="${rules}\n  <!-- End Bashboard ImageMagick Security -->"
            sed -i "s|</policymap>|  ${rules}\n</policymap>|" "$pol"
        done
    }
    run_task "Hardening ImageMagick policy.xml (blocking RCE coders)" harden_imagemagick_policy

    run_task "Validating PHP ${PHP_VER}-FPM configuration syntax" "/usr/sbin/php-fpm${PHP_VER}" -t
    run_task "Enabling and starting PHP ${PHP_VER}-FPM service" systemctl enable --now "php${PHP_VER}-fpm"
    systemctl restart "php${PHP_VER}-fpm" >> "$INSTALL_LOG" 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 11. COMPONENT 4: REDIS OBJECT CACHE (SHA-256 ACLs & Explicit Loopback Bind)
# ------------------------------------------------------------------------------
if [ "$INSTALL_REDIS" -eq 1 ]; then
    echo -e "\n${BLUE}--- [4/6] Configuring Redis Cache Subsystem (SHA-256 ACL Isolated) ---${NC}"
    run_task "Installing Redis Server" apt-get install -y redis-server

    configure_hardened_redis() {
        local redis_conf="/etc/redis/redis.conf"
        local acl_file="/etc/redis/users.acl"
        local admin_cred="/etc/bashboard/redis-admin.cred"

        [ -f "$redis_conf" ] || return 1

        # Generate or reuse persistent root-only Redis admin password (idempotent)
        local admin_pass=""
        if [ -f "$admin_cred" ] && [ ! -L "$admin_cred" ]; then
            admin_pass=$(grep -E '^REDIS_ADMIN_PASS=' "$admin_cred" 2>/dev/null | cut -d'=' -f2- || true)
        fi
        if [ -z "$admin_pass" ]; then
            admin_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
            (
                umask 077
                cat > "$admin_cred" <<EOF
REDIS_ADMIN_USER=bashboard_admin
REDIS_ADMIN_PASS=${admin_pass}
EOF
                chown root:root "$admin_cred"
                chmod 600 "$admin_cred"
            )
        fi

        # Store SHA-256 hash (#<hex>) in users.acl instead of plaintext password (>pass)
        local admin_sha256
        admin_sha256=$(printf '%s' "$admin_pass" | sha256sum | awk '{print $1}')

        # Detect Redis version to safely handle &* pubsub selector (introduced in Redis 6.2)
        local r_ver r_maj r_min pubsub_sel=""
        r_ver=$(redis-server -v 2>&1 | grep -oE 'v=[0-9]+\.[0-9]+' | cut -d= -f2 || echo "6.0")
        r_maj=$(echo "$r_ver" | cut -d. -f1)
        r_min=$(echo "$r_ver" | cut -d. -f2)
        if [ "${r_maj:-6}" -gt 6 ] || { [ "${r_maj:-6}" -eq 6 ] && [ "${r_min:-0}" -ge 2 ]; }; then
            pubsub_sel=" &*"
        fi

        # Preserve any existing per-tenant ACL entries (user v_*) when re-running installer
        local existing_tenants=""
        if [ -f "$acl_file" ] && [ ! -L "$acl_file" ]; then
            existing_tenants=$(grep -E '^user v_[a-z0-9_]+ ' "$acl_file" 2>/dev/null || true)
        fi

        (
            umask 077
            {
                echo "user default off"
                echo "user bashboard_admin on #${admin_sha256} ~*${pubsub_sel} +@all"
                if [ -n "$existing_tenants" ]; then
                    echo "$existing_tenants"
                fi
            } > "$acl_file"
            chown redis:redis "$acl_file" 2>/dev/null || chown root:redis "$acl_file" 2>/dev/null || true
            chmod 640 "$acl_file"
        )

        # Explicitly enforce loopback bind (never rely on distro defaults)
        local bind_line="bind 127.0.0.1"
        if ip -6 addr show dev lo 2>/dev/null | grep -q '::1'; then
            bind_line="bind 127.0.0.1 -::1"
        fi

        sed -i -E "s/^supervised (no|auto)/supervised systemd/" "$redis_conf"
        sed -i "/# Bashboard Redis Security/,/# End Bashboard Redis Security/d" "$redis_conf"

        # Note: FLUSHALL/FLUSHDB are strictly blocked per-tenant in ACLs while remaining available to bashboard_admin
        cat >> "$redis_conf" <<EOF

# Bashboard Redis Security (Loopback Bind, SHA-256 ACLs & Infrastructure Command Lockdown)
${bind_line}
protected-mode yes
maxmemory-policy allkeys-lru
aclfile /etc/redis/users.acl
rename-command KEYS ""
rename-command MONITOR ""
rename-command CONFIG ""
rename-command SHUTDOWN ""
rename-command DEBUG ""
rename-command BGSAVE ""
rename-command SAVE ""
rename-command SLAVEOF ""
rename-command REPLICAOF ""
# End Bashboard Redis Security
EOF

        systemctl enable redis-server || return 1
        systemctl restart redis-server || return 1
        systemctl is-active --quiet redis-server || return 1

        # Verify SHA-256 ACL authentication works
        REDISCLI_AUTH="$admin_pass" redis-cli --user bashboard_admin PING | grep -qx "PONG"
    }

    run_task "Enforcing Redis loopback bind & SHA-256 ACL isolation" configure_hardened_redis
fi

# ------------------------------------------------------------------------------
# 12. COMPONENT 5: WP-CLI ORCHESTRATION TOOL (SHA-512 Verified + Unprivileged Test)
# ------------------------------------------------------------------------------
if [ "$INSTALL_WPCLI" -eq 1 ]; then
    echo -e "\n${BLUE}--- [5/6] Deploying WP-CLI Framework (SHA-512 Verified) ---${NC}"
    install_verified_wpcli() {
        local tmp_wp tmp_sha expected_hash
        tmp_wp=$(mktemp /tmp/wpcli_XXXXXX.phar)
        tmp_sha=$(mktemp /tmp/wpcli_XXXXXX.sha512)
        trap 'rm -f "${tmp_wp:-}" "${tmp_sha:-}"' RETURN

        curl -fsSL -o "$tmp_wp" https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || return 1
        curl -fsSL -o "$tmp_sha" https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar.sha512 || return 1

        expected_hash=$(awk '{print $1}' "$tmp_sha" | tr -d '[:space:]')
        [[ "$expected_hash" =~ ^[0-9a-fA-F]{128}$ ]] || return 1

        echo "${expected_hash}  ${tmp_wp}" | sha512sum -c - || return 1

        chmod 755 "$tmp_wp"
        # Smoke-test verified PHAR strictly as unprivileged 'nobody', never as root
        runuser -u nobody -- php "$tmp_wp" --info >/dev/null 2>&1 || return 1

        chown root:root "$tmp_wp"
        mv -f "$tmp_wp" /usr/local/bin/wp
        tmp_wp=""
    }
    run_task "Downloading & SHA-512 verifying WP-CLI binary" install_verified_wpcli
fi

# ------------------------------------------------------------------------------
# 13. COMPONENT 6: SANDBOXED PHPMYADMIN (127.0.0.1:8080 SSH-TUNNEL ONLY)
# ------------------------------------------------------------------------------
if [ "$INSTALL_PMA" -eq 1 ]; then
    echo -e "\n${BLUE}--- [6/6] Deploying Sandboxed phpMyAdmin (SSH-Tunnel :8080) ---${NC}"

    PMA_PHP_VER="$PHP_VER"
    if [ ! -x "/usr/sbin/php-fpm${PMA_PHP_VER}" ]; then
        PMA_PHP_VER=$(detect_installed_phps | awk -F',' '{print $NF}' | tr -d '[:space:]')
    fi
    if [ -z "$PMA_PHP_VER" ] || [ ! -x "/usr/sbin/php-fpm${PMA_PHP_VER}" ]; then
        echo -e "   ${RED}❌ [FATAL] phpMyAdmin requires an installed PHP-FPM binary. Enable PHP-FPM [Option 3] first.${NC}" >&2
        exit 1
    fi

    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect" | debconf-set-selections 2>/dev/null || true
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean false" | debconf-set-selections 2>/dev/null || true

    run_task "Installing phpMyAdmin package (Non-Interactive)" \
        apt-get install -y --no-install-recommends phpmyadmin

    provision_pma_pool() {
        local pma_user='v_pma_sys'
        local pma_tmp='/var/lib/phpmyadmin/tmp'
        local pma_sock="/run/php/php${PMA_PHP_VER}-fpm-phpmyadmin.sock"
        local pma_pool="/etc/php/${PMA_PHP_VER}/fpm/pool.d/phpmyadmin.conf"

        getent group "$pma_user" >/dev/null 2>&1 || groupadd -r "$pma_user"
        id -u "$pma_user" >/dev/null 2>&1 || useradd -r -g "$pma_user" -s /usr/sbin/nologin -d /var/lib/phpmyadmin -M "$pma_user"

        mkdir -p "$pma_tmp" /run/php "/etc/php/${PMA_PHP_VER}/fpm/pool.d"
        chown -R "${pma_user}:www-data" /var/lib/phpmyadmin
        chmod 700 "$pma_tmp"
        if [ -f /etc/phpmyadmin/config-db.php ]; then
            chown "root:${pma_user}" /etc/phpmyadmin/config-db.php 2>/dev/null || true
            chmod 640 /etc/phpmyadmin/config-db.php 2>/dev/null || true
        fi

        if [ ! -f /var/lib/phpmyadmin/blowfish_secret.inc.php ] || ! grep -q "blowfish_secret" /var/lib/phpmyadmin/blowfish_secret.inc.php 2>/dev/null; then
            local bf_secret
            bf_secret=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
            printf "<?php\n\$cfg['blowfish_secret'] = '%s';\n" "$bf_secret" > /var/lib/phpmyadmin/blowfish_secret.inc.php
            chown "${pma_user}:${pma_user}" /var/lib/phpmyadmin/blowfish_secret.inc.php
            chmod 600 /var/lib/phpmyadmin/blowfish_secret.inc.php
        fi

        cat > "$pma_pool" <<EOF
; ==============================================================================
; Bashboard Isolated phpMyAdmin Pool (Zero Access to /var/www/* Tenants)
; ==============================================================================
[phpmyadmin]
user = ${pma_user}
group = ${pma_user}

listen = ${pma_sock}
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = 4
pm.process_idle_timeout = 10s
pm.max_requests = 200

request_terminate_timeout = 300s

php_admin_flag[log_errors] = on
php_admin_flag[expose_php] = off
php_admin_value[upload_tmp_dir] = ${pma_tmp}
php_admin_value[session.save_path] = ${pma_tmp}
php_admin_value[sys_temp_dir] = ${pma_tmp}

; Strict Jail: Completely blocks phpMyAdmin from reading /var/www/* tenant files
php_admin_value[open_basedir] = /usr/share/phpmyadmin/:/etc/phpmyadmin/:/var/lib/phpmyadmin/:/usr/share/php/:/usr/share/javascript/:/dev/urandom:/usr/share/zoneinfo/
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec,pcntl_fork,pcntl_signal,pcntl_alarm,dl,putenv,show_source,highlight_file,proc_get_status,opcache_get_status,opcache_get_configuration,posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,posix_setuid,posix_geteuid,posix_getpwuid

php_value[memory_limit] = 256M
php_value[upload_max_filesize] = 256M
php_value[post_max_size] = 256M
php_value[max_execution_time] = 300
EOF

        # Validate strictly BEFORE restarting live PHP-FPM daemon
        if ! "/usr/sbin/php-fpm${PMA_PHP_VER}" -t; then
            rm -f "$pma_pool"
            return 1
        fi
        systemctl restart "php${PMA_PHP_VER}-fpm"
    }
    run_task "Provisioning isolated phpMyAdmin FPM pool (v_pma_sys)" provision_pma_pool

    configure_pma_nginx() {
        rm -f /etc/nginx/sites-enabled/phpmyadmin /etc/nginx/sites-available/phpmyadmin

        # Guarantee rate-limit zone exists even if Nginx option was unchecked during this run
        if [ ! -f "/etc/nginx/conf.d/00-bashboard-rate-limit.conf" ]; then
            printf "%s\n" \
                "# Bashboard Global Security Zone: Mitigates Login Brute-Force" \
                "limit_req_zone \$binary_remote_addr zone=wplogin:10m rate=10r/m;" \
                "limit_req_status 429;" > "/etc/nginx/conf.d/00-bashboard-rate-limit.conf"
        fi

        # NOTE: Deny regex blocks MUST precede 'location ~ \.php$' in Nginx (first-regex-match wins)
        cat > /etc/nginx/conf.d/00-bashboard-phpmyadmin.conf <<EOF
# Bashboard Zero-Public-Exposure phpMyAdmin Listener (SSH Tunnel Only)
server {
    listen 127.0.0.1:8080;
    server_name _;

    root /usr/share/phpmyadmin;
    index index.php index.html;

    access_log off;
    error_log /var/log/nginx/phpmyadmin_error.log;

    server_tokens off;
    client_max_body_size 256M;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Block hidden files & sensitive phpMyAdmin directories BEFORE PHP regex matching
    location ~ /\. {
        deny all;
    }

    location ~* ^/(?:libraries|setup|templates|locale|sql)(?:/|$) {
        deny all;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        limit_req zone=wplogin burst=20 nodelay;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PMA_PHP_VER}-fpm-phpmyadmin.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 300s;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }
}
EOF
        if ! nginx -t; then
            rm -f /etc/nginx/conf.d/00-bashboard-phpmyadmin.conf
            return 1
        fi
        systemctl reload nginx
    }
    run_task "Binding phpMyAdmin Nginx listener to 127.0.0.1:8080" configure_pma_nginx
fi

# ------------------------------------------------------------------------------
# 14. PROVISIONING VERIFICATION & STATUS REPORT
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}=================================================================="
echo -e "   🎉 LEMP STACK PROVISIONING FINISHED SUCCESSFULLY"
echo -e "==================================================================${NC}"
[ "$INSTALL_NGINX" -eq 1 ] && printf "   %-20s: %b\n" "Nginx Status" "$(systemctl is-active --quiet nginx && echo "${GREEN}● ACTIVE${NC}" || echo "${RED}○ FAILED${NC}")"
[ "$INSTALL_MARIADB" -eq 1 ] && printf "   %-20s: %b\n" "MariaDB Status" "$(systemctl is-active --quiet mariadb && echo "${GREEN}● ACTIVE${NC}" || echo "${RED}○ FAILED${NC}")"
[ "$INSTALL_PHP" -eq 1 ] && printf "   %-20s: %b\n" "PHP-FPM Engine" "$(systemctl is-active --quiet "php${PHP_VER}-fpm" && echo "${GREEN}● ACTIVE (v${PHP_VER})${NC}" || echo "${RED}○ FAILED${NC}")"
[ "$INSTALL_REDIS" -eq 1 ] && printf "   %-20s: %b\n" "Redis Status" "$(systemctl is-active --quiet redis-server && echo "${GREEN}● ACTIVE (SHA-256 ACL | Default Off)${NC}" || echo "${RED}○ FAILED${NC}")"
[ "$INSTALL_WPCLI" -eq 1 ] && printf "   %-20s: %b\n" "WP-CLI Command" "$(command -v wp >/dev/null && echo "${GREEN}● READY (SHA-512 Verified)${NC}" || echo "${RED}○ MISSING${NC}")"
if [ "$INSTALL_PMA" -eq 1 ] && [ -f "/etc/nginx/conf.d/00-bashboard-phpmyadmin.conf" ]; then
    srv_ip=$(cat /run/bashboard_ip 2>/dev/null || echo "SERVER_IP")
    ssh_hint_user="${SUDO_USER:-your_ssh_user}"
    printf "   %-20s: %b\n" "phpMyAdmin" "${GREEN}● ISOLATED ON 127.0.0.1:8080 (Pool: v_pma_sys / PHP ${PMA_PHP_VER})${NC}"
    echo -e "   ${GRAY}--------------------------------------------------------------${NC}"
    echo -e "   🔒 ${CYAN}SSH Tunnel Command (Run on your laptop):${NC}"
    echo -e "      ${YELLOW}ssh -L 8081:127.0.0.1:8080 ${ssh_hint_user}@${srv_ip}${NC}"
    echo -e "      Then open in browser: ${WHITE}http://localhost:8081${NC}"
fi
echo -e "${GREEN}==================================================================${NC}"
exit 0