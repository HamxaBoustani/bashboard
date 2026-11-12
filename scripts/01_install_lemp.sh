#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD MODULE: [01] Enterprise LEMP Stack Interactive TUI Installer
# Version:          1.1.0 (Production Hardened: Dual-OS Sury/PPA Engine, Default
#                   VHost Unlink, Dual-Auth MariaDB Socket+Pass, DNS Utilities)
# Architecture:     Interactive TUI | Dynamic Discovery | Global Infrastructure Base
# Platform:         Debian 11/12 (Bullseye/Bookworm), Ubuntu 20.04/22.04/24.04/26.04 LTS
# ==============================================================================
set -euo pipefail

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
# 2. RUNTIME OS DETECTION & ENVIRONMENT ASSERTION
# ------------------------------------------------------------------------------
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
touch "$INSTALL_LOG" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. DYNAMIC PHP SOCKET & FILESYSTEM AUTODISCOVERY
# ------------------------------------------------------------------------------
detect_installed_phps() {
    local phps=()

    # Scan live unix sockets
    for sock in /run/php/php*-fpm.sock /var/run/php/php*-fpm.sock; do
        if [ -S "$sock" ]; then
            local ver
            ver=$(basename "$sock" | grep -oE '[0-9]+\.[0-9]+' || true)
            [[ -n "$ver" ]] && phps+=("$ver")
        fi
    done

    # Scan installed configuration trees
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

SYSTEM_PHPS=$(detect_installed_phps)
LATEST_DETECTED_PHP=$(echo "$SYSTEM_PHPS" | awk -F',' '{print $NF}' | xargs)
PHP_VER="${LATEST_DETECTED_PHP:-8.3}"

# Default component toggle states
INSTALL_NGINX=1
INSTALL_MARIADB=1
INSTALL_PHP=1
INSTALL_REDIS=1
INSTALL_WPCLI=1
DB_ROOT_PASS=""

# ------------------------------------------------------------------------------
# 4. TUI STATUS INDICATORS & HELPERS
# ------------------------------------------------------------------------------
detect_installed() {
    local bin="$1"
    if command -v "$bin" >/dev/null 2>&1; then
        echo -e "${GREEN}● INSTALLED${NC}"
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

# ------------------------------------------------------------------------------
# 5. TUI DASHBOARD RENDERER
# ------------------------------------------------------------------------------
draw_tui() {
    clear
    local st_nginx st_mariadb st_php st_redis st_wpcli
    st_nginx=$(detect_installed nginx)
    st_mariadb=$(detect_installed mariadb)
    [[ "$st_mariadb" == *"NOT INSTALLED"* ]] && st_mariadb=$(detect_installed mysql)
    st_php=$(detect_php_status)
    st_redis=$(detect_installed redis-server)
    st_wpcli=$(detect_installed wp)

    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Module: %-25s${NC}\n" "BASHBOARD LEMP SUITE" "LEMP Installer TUI"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   📋 ${PURPLE}${BOLD}COMPONENT SELECTION & ENVIRONMENT STATUS${NC}"
    echo -e "      Target Distribution: ${WHITE}${NAME:-Linux} (${OS_CODENAME})${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    
    printf "   ${CYAN}[1]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_NGINX")" "Nginx Web Server" "$st_nginx"
    printf "   ${CYAN}[2]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_MARIADB")" "MariaDB SQL Server" "$st_mariadb"
    printf "   ${CYAN}[3]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_PHP")" "PHP-FPM Engine" "$st_php"
    printf "   ${CYAN}[4]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_REDIS")" "Redis Object Cache" "$st_redis"
    printf "   ${CYAN}[5]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Current Status: %b\n" "$(toggle_status "$INSTALL_WPCLI")" "WP-CLI Core CLI" "$st_wpcli"
    
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ⚙️  ${PURPLE}${BOLD}STACK TUNING PARAMETERS${NC}"
    printf "      %-22s: ${YELLOW}%-22s${NC}${COL_MID}${GRAY}│${NC} Change with: ${CYAN}[6]${NC}\n" "Target PHP Version" "v${PHP_VER} $([[ ",$SYSTEM_PHPS," == *",$PHP_VER,"* ]] && echo "(Installed)")"
    
    local db_pass_disp="Auto-Socket (Preserved)"
    if [ -n "$DB_ROOT_PASS" ]; then db_pass_disp="Dual (Socket + Pass)"; fi
    printf "      %-22s: ${YELLOW}%-22s${NC}${COL_MID}${GRAY}│${NC} Change with: ${CYAN}[7]${NC}\n" "MariaDB Root Pass" "$db_pass_disp"
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
        6)
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
        7)
            echo ""
            read -rsp "   Set MariaDB Root Password (leave blank for unix_socket only): " user_db_pass
            echo ""
            DB_ROOT_PASS="$user_db_pass"
            ;;
        9)
            if [ "$INSTALL_NGINX" -eq 0 ] && [ "$INSTALL_MARIADB" -eq 0 ] && [ "$INSTALL_PHP" -eq 0 ] && [ "$INSTALL_REDIS" -eq 0 ] && [ "$INSTALL_WPCLI" -eq 0 ]; then
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
# 7. PROVISIONING ENGINE & STRUCTURED TASK LOGGER
# ==============================================================================
clear
echo -e "${CYAN}==================================================================${NC}"
echo -e "   🚀 ${BOLD}${WHITE}Executing Production LEMP Stack Provisioning...${NC}"
echo -e "   📄 Detailed Log File: ${YELLOW}${INSTALL_LOG}${NC}"
echo -e "${CYAN}==================================================================${NC}\n"

export DEBIAN_FRONTEND=noninteractive

run_task() {
    local task_name="$1"
    shift
    printf "   %-55s ... " "$task_name"
    echo -e "\n--- [$(date '+%Y-%m-%d %H:%M:%S')] TASK: $task_name ---" >> "$INSTALL_LOG"

    if "$@" >> "$INSTALL_LOG" 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
        return 0
    else
        echo -e "${RED}[FAILED]${NC}"
        echo -e "\n${RED}Task failed! Inspect error log with:${NC} tail -n 40 $INSTALL_LOG" >&2
        return 1
    fi
}

run_task "Updating APT package index" apt-get update -y
run_task "Installing base build & DNS utilities" apt-get install -y --no-install-recommends \
    software-properties-common curl wget gnupg2 ca-certificates lsb-release ufw unzip dnsutils

# ------------------------------------------------------------------------------
# 8. COMPONENT 1: NGINX WEBSERVER & GLOBAL CLOUDFLARE/SECURITY PRIMITIVES
# ------------------------------------------------------------------------------
if [ "$INSTALL_NGINX" -eq 1 ]; then
    echo -e "\n${BLUE}--- [1/5] Configuring Nginx Web Server & Global Primitives ---${NC}"
    run_task "Installing Nginx package" apt-get install -y nginx
    run_task "Enabling and starting Nginx daemon" systemctl enable --now nginx

    mkdir -p /etc/nginx/snippets /etc/nginx/ssl /etc/nginx/conf.d

    # Remove default stock symlink to prevent Certbot --nginx parser collisions
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

    # 8.3 Global Cloudflare Real-IP Ingestion Engine (IPv4 & IPv6 with offline fallback)
    run_task "Configuring Cloudflare Real-IP Ingestion (00-cloudflare-realip.conf)" bash -c '
        cf_conf="/etc/nginx/conf.d/00-cloudflare-realip.conf"
        cat > "$cf_conf" <<\EOF
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
    '

    # 8.4 Global Rate-Limit Zone (Rate: 10r/m, Status: 429)
    run_task "Deploying Global Login Rate-Limit Zone (00-bashboard-rate-limit.conf)" bash -c '
        rl_conf="/etc/nginx/conf.d/00-bashboard-rate-limit.conf"
        printf "%s\n" \
            "# Bashboard Global Security Zone: Mitigates WordPress Login Brute-Force" \
            "limit_req_zone \$binary_remote_addr zone=wplogin:10m rate=10r/m;" \
            "limit_req_status 429;" > "$rl_conf"
    '

    # Validate syntax and reload
    run_task "Validating Nginx configuration syntax" nginx -t
    systemctl reload nginx >> "$INSTALL_LOG" 2>&1 || true

    if command -v ufw >/dev/null 2>&1; then
        ufw allow 'Nginx Full' >> "$INSTALL_LOG" 2>&1 || true
    fi
fi

# ------------------------------------------------------------------------------
# 9. COMPONENT 2: MARIADB DATABASE ENGINE
# ------------------------------------------------------------------------------
if [ "$INSTALL_MARIADB" -eq 1 ]; then
    echo -e "\n${BLUE}--- [2/5] Configuring MariaDB Database Server ---${NC}"
    run_task "Installing MariaDB Server & Client" apt-get install -y mariadb-server mariadb-client
    run_task "Enabling and starting MariaDB daemon" systemctl enable --now mariadb

    DB_CMD="mariadb"
    if ! mariadb -u root -e "SELECT 1;" >/dev/null 2>&1; then
        if [ -n "$DB_ROOT_PASS" ]; then
            DB_CMD="mariadb -u root -p${DB_ROOT_PASS}"
        fi
    fi

    $DB_CMD <<EOSQL >> "$INSTALL_LOG" 2>&1 || true
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOSQL

    if [ -n "$DB_ROOT_PASS" ]; then
        # Preserve unix_socket alongside password so headless root scripts (backups/VHost) never break
        run_task "Setting MariaDB root credentials (preserving unix_socket)" \
            $DB_CMD -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('${DB_ROOT_PASS}'); FLUSH PRIVILEGES;"
    else
        echo -e "   ${GRAY}MariaDB root left with native unix_socket authentication (Secure).${NC}"
    fi
fi

# ------------------------------------------------------------------------------
# 10. COMPONENT 3: PHP-FPM POOL & EXTENSION SUBSYSTEM
# ------------------------------------------------------------------------------
if [ "$INSTALL_PHP" -eq 1 ]; then
    echo -e "\n${BLUE}--- [3/5] Configuring PHP ${PHP_VER}-FPM Engine & Modules ---${NC}"
    
    # OS-Specific Repository Routing
    if [ "$OS_ID" = "ubuntu" ]; then
        if [ "$OS_CODENAME" != "resolute" ] && ! grep -q "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
            run_task "Adding Ondrej PHP PPA for Ubuntu" add-apt-repository -y ppa:ondrej/php
            run_task "Refreshing APT cache for Ubuntu PPA" apt-get update -y
        fi
    elif [ "$OS_ID" = "debian" ]; then
        if [ ! -f "/etc/apt/sources.list.d/sury-php.list" ]; then
            run_task "Registering Sury PHP Keyring for Debian" bash -c '
                mkdir -p -m 0755 /etc/apt/keyrings
                curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/keyrings/sury-php.gpg
                echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ '"${OS_CODENAME}"' main" > /etc/apt/sources.list.d/sury-php.list
            '
            run_task "Refreshing APT cache for Debian Sury" apt-get update -y
        fi
    fi

    PHP_MODULES=(
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
        "php${PHP_VER}-imagick"
        "php${PHP_VER}-redis"
        "php${PHP_VER}-opcache"
        "php${PHP_VER}-readline"
    )

    run_task "Installing PHP ${PHP_VER}-FPM core & enterprise extensions" \
        apt-get install -y "${PHP_MODULES[@]}"

    php_ini_file="/etc/php/${PHP_VER}/fpm/php.ini"
    if [ -f "$php_ini_file" ]; then
        run_task "Tuning PHP-FPM php.ini limits (128M Upload / 512M Memory)" bash -c "
            sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 128M/' '$php_ini_file'
            sed -i 's/^post_max_size = .*/post_max_size = 128M/' '$php_ini_file'
            sed -i 's/^memory_limit = .*/memory_limit = 512M/' '$php_ini_file'
            sed -i 's/^max_execution_time = .*/max_execution_time = 300/' '$php_ini_file'
            sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' '$php_ini_file'
        "
    fi

    run_task "Enabling and starting PHP ${PHP_VER}-FPM service" systemctl enable --now "php${PHP_VER}-fpm"
    systemctl restart "php${PHP_VER}-fpm" >> "$INSTALL_LOG" 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 11. COMPONENT 4: REDIS OBJECT CACHE ENGINE
# ------------------------------------------------------------------------------
if [ "$INSTALL_REDIS" -eq 1 ]; then
    echo -e "\n${BLUE}--- [4/5] Configuring Redis Cache Subsystem ---${NC}"
    run_task "Installing Redis Server" apt-get install -y redis-server
    
    if [ -f "/etc/redis/redis.conf" ]; then
        run_task "Enforcing systemd supervision in redis.conf" \
            sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
    fi

    run_task "Enabling and restarting Redis Service" bash -c "
        systemctl enable redis-server && systemctl restart redis-server
    "
fi

# ------------------------------------------------------------------------------
# 12. COMPONENT 5: WP-CLI ORCHESTRATION TOOL
# ------------------------------------------------------------------------------
if [ "$INSTALL_WPCLI" -eq 1 ]; then
    echo -e "\n${BLUE}--- [5/5] Deploying WP-CLI Framework ---${NC}"
    run_task "Downloading and verifying WP-CLI binary" bash -c '
        tmp_wp=$(mktemp /tmp/wpcli_XXXXXX.phar)
        curl -fsSL -o "$tmp_wp" https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        
        if ! test -s "$tmp_wp"; then
            rm -f "$tmp_wp"
            exit 1
        fi
        
        if ! php "$tmp_wp" --info >/dev/null 2>&1; then
            rm -f "$tmp_wp"
            exit 1
        fi
        
        chmod +x "$tmp_wp"
        mv "$tmp_wp" /usr/local/bin/wp
    '
fi

# ------------------------------------------------------------------------------
# 13. PROVISIONING VERIFICATION & STATUS REPORT
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}=================================================================="
echo -e "   🎉 LEMP STACK PROVISIONING FINISHED SUCCESSFULLY"
echo -e "==================================================================${NC}"
[ "$INSTALL_NGINX" -eq 1 ] && printf "   %-20s: %b\n" "Nginx Status" "$(systemctl is-active --quiet nginx && echo "${GREEN}● ACTIVE${NC}" || echo "${RED}○ FAILED${NC}")"
[ "$INSTALL_MARIADB" -eq 1 ] && printf "   %-20s: %b\n" "MariaDB Status" "$(systemctl is-active --quiet mariadb && echo "${GREEN}● ACTIVE${NC}" || echo "${RED}○ FAILED${NC}")"
[ "$INSTALL_PHP" -eq 1 ] && printf "   %-20s: %b\n" "PHP-FPM Engine" "$(systemctl is-active --quiet "php${PHP_VER}-fpm" && echo "${GREEN}● ACTIVE (v${PHP_VER})${NC}" || echo "${RED}○ FAILED${NC}")"
[ "$INSTALL_REDIS" -eq 1 ] && printf "   %-20s: %b\n" "Redis Status" "$(systemctl is-active --quiet redis-server && echo "${GREEN}● ACTIVE${NC}" || echo "${RED}○ FAILED${NC}")"
[ "$INSTALL_WPCLI" -eq 1 ] && printf "   %-20s: %b\n" "WP-CLI Command" "$(command -v wp >/dev/null && echo "${GREEN}● READY (/usr/local/bin/wp)${NC}" || echo "${RED}○ MISSING${NC}")"
echo -e "${GREEN}==================================================================${NC}"
exit 0