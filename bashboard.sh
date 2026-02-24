#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD - Enterprise VPS Management System
# Version:      0.8 (Zero-Crash SRE Build - Full Version)
# Architecture: Multi-Tier | Active Caching | 100% Absolute Alignment
# Highlights:   Set-e Safe Logic, Anti-Symlink Lock, DBus Hang Prevention
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CORE CONFIGURATION & STRICT MODE
# ------------------------------------------------------------------------------
set -euo pipefail

ESC=$(printf '\033')
B_O=$(printf '\133')
B_C=$(printf '\135')

# ------------------------------------------------------------------------------
# 2. TERMINAL UI, COLORS & SENSORS
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

TERM_COLS=$(tput cols 2>/dev/null || echo 100)
if [ "$TERM_COLS" -lt 95 ]; then
    echo -e "${YELLOW}Warning: Terminal width ($TERM_COLS) is too narrow. UI may distort.${NC}"
    echo -e "${GRAY}Recommended: 95+ columns. Starting in 3 seconds...${NC}"
    sleep 3
fi

# ------------------------------------------------------------------------------
# 3. TRAP HANDLER (Universal UI Restore)
# ------------------------------------------------------------------------------
cleanup_env() {
    local exit_code=$?
    tput cnorm 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup_env EXIT INT TERM

check_requirements() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}${BOLD}Error:${NC} Bashboard must be run as root.${NC}"
        exit 1
    fi
}
check_requirements

# ------------------------------------------------------------------------------
# 4. ZERO-TRUST LOCKING & SECURE LOGGING
# ------------------------------------------------------------------------------
readonly SCRIPT_DIR="$( cd "$( dirname "$0" )" >/dev/null 2>&1 && pwd )/scripts"

if [ -d "/run" ]; then 
    readonly LOCK_FILE="/run/bashboard.lock"
else 
    readonly LOCK_FILE="/var/run/bashboard.lock"
fi

# 🛡️ Scoped Hardening: Protect lock file safely
old_umask=$(umask)
umask 077

if [ -L "$LOCK_FILE" ]; then 
    echo -e "${RED}Security Alert: Lock file is a symlink! Aborting.${NC}"
    exit 1
fi

if [ -e "$LOCK_FILE" ]; then
    if [ "$(stat -c '%u' "$LOCK_FILE" 2>/dev/null)" != "$EUID" ]; then
        echo -e "${RED}Security Alert: Lock file owned by another user! Aborting.${NC}"
        exit 1
    fi
fi

if ! exec 200>>"$LOCK_FILE"; then
    echo -e "${RED}Error: Cannot acquire lock file FD.${NC}"
    exit 1
fi

if ! flock -n 200; then
    echo -e "${RED}Error: Another instance of Bashboard is already running.${NC}"
    exit 1
fi

if touch "/var/log/bashboard.log" 2>/dev/null; then 
    readonly LOG_FILE="/var/log/bashboard.log"
else 
    readonly LOG_FILE="/tmp/bashboard.log"
    touch "$LOG_FILE" 2>/dev/null || true
fi

# Restore original umask for safe subsystem execution
umask "$old_umask"

log_action() {
    local status="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ($status) - $message" >> "$LOG_FILE" || true
}

if command -v systemctl >/dev/null 2>&1; then 
    readonly HAS_SYSTEMD=1
else 
    readonly HAS_SYSTEMD=0
fi

# ------------------------------------------------------------------------------
# 5. SRE CACHING LAYER & ANTI-HANG WRAPPERS
# ------------------------------------------------------------------------------
safe_cmd() {
    local cmd="$1"
    shift
    if ! command -v "$cmd" >/dev/null 2>&1; then 
        return 127
    fi
    
    if command -v timeout >/dev/null 2>&1; then
        env PAGER=cat timeout 2 "$cmd" "$@" </dev/null || true
    else
        env PAGER=cat "$cmd" "$@" </dev/null || true
    fi
}

get_static_info() {
    echo -e "${YELLOW}Gathering system footprint, please wait...${NC}"
    
    OS=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown Linux")
    KERNEL=$(safe_cmd uname -r || echo "Unknown")
    CPU_MODEL=$(awk -F: 'tolower($1) ~ /^model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "Unknown")
    CPU_CORES=$(safe_cmd nproc || echo "1")
    
    DISK_TYPE="Unknown"
    local has_hdd=0
    for d in /sys/block/nvme* /sys/block/vd* /sys/block/sd* /sys/block/hd*; do
        if [ -f "$d/queue/rotational" ]; then
            local rot
            rot=$(cat "$d/queue/rotational" 2>/dev/null || true)
            if [ "$rot" = "0" ]; then 
                DISK_TYPE="SSD / NVMe"
                break
            elif [ "$rot" = "1" ]; then 
                has_hdd=1
            fi
        fi
    done
    if [ "$DISK_TYPE" = "Unknown" ]; then
        if [ "$has_hdd" -eq 1 ]; then 
            DISK_TYPE="HDD"
        fi
    fi

    PUBLIC_IP="Blocked/Fail"
    if command -v curl >/dev/null 2>&1; then 
        local _ip=""
        _ip=$(safe_cmd curl -4 -s --connect-timeout 2 --max-time 2 https://api.ipify.org 2>/dev/null || true)
        if ! [[ "$_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            _ip=$(safe_cmd curl -4 -s --connect-timeout 2 --max-time 2 https://ifconfig.me 2>/dev/null || true)
        fi
        if ! [[ "$_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            _ip=$(safe_cmd curl -4 -s --connect-timeout 2 --max-time 2 https://icanhazip.com 2>/dev/null || true)
        fi
        if [[ "$_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then 
            PUBLIC_IP="$_ip"
        fi
    else 
        PUBLIC_IP="Curl missing"
    fi
    
    LOCAL_IP=$(safe_cmd hostname -I 2>/dev/null | awk '{print $1}' || echo "Unavailable")
    HOSTNAME=$(safe_cmd hostname 2>/dev/null || echo "Unknown")
    ARCH=$(safe_cmd uname -m 2>/dev/null || echo "Unknown")

    if [ "$HAS_SYSTEMD" -eq 1 ]; then 
        VIRT=$(safe_cmd systemd-detect-virt 2>/dev/null || echo "Dedicated")
    else 
        VIRT="Unknown"
    fi
    if echo "$VIRT" | grep -qi "none"; then 
        VIRT="Dedicated"
    fi
    VIRT=$(awk '{print toupper(substr($0,1,1)) substr($0,2)}' <<< "$VIRT" 2>/dev/null || echo "$VIRT")

    OS="${OS:0:22}"; KERNEL="${KERNEL:0:22}"; HOSTNAME="${HOSTNAME:0:22}"; VIRT="${VIRT:0:22}"; CPU_MODEL="${CPU_MODEL:0:65}"

    V_NGINX=$(safe_cmd nginx -v 2>&1 | grep -oE 'nginx/[0-9.]+' | cut -d/ -f2 || true)
    V_APACHE=$(safe_cmd apache2 -v 2>&1 | awk -F'/' '/Apache/ {print $2}' | awk '{print $1}' || true)
    if [ -z "$V_APACHE" ]; then 
        V_APACHE=$(safe_cmd httpd -v 2>&1 | awk -F'/' '/Apache/ {print $2}' | awk '{print $1}' || true)
    fi
    
    V_MYSQL=$(safe_cmd mysql -V 2>&1 | grep -oEi 'mariadb.*[0-9]+\.[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
    V_REDIS=$(safe_cmd redis-server -v 2>&1 | grep -oE 'v=[0-9.]+' | cut -d= -f2 || true)
    
    local FPM_VERSIONS
    FPM_VERSIONS=$( (ls -1 /etc/php/*/fpm/php-fpm.conf 2>/dev/null || true) | awk -F'/' '{print $4}' | sort -V | paste -sd "," - | sed 's/,/, /g' || true )
    if [ -n "$FPM_VERSIONS" ]; then 
        V_PHP="$FPM_VERSIONS"
    else 
        V_PHP=$(safe_cmd php -v 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)
    fi
    
    V_WP=$(safe_cmd wp --allow-root --skip-wordpress --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)
    V_GIT=$(safe_cmd git --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)
    V_NODE=$(safe_cmd node -v 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)
    V_COMP=$(COMPOSER_DISABLE_NETWORK=1 COMPOSER_ALLOW_SUPERUSER=1 safe_cmd composer --version --no-interaction 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)

    PHP_SVC_NAME="php-fpm"
    if [ "$HAS_SYSTEMD" -eq 1 ]; then
        local _php_svcs
        _php_svcs=$(safe_cmd systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -ioE '^php[0-9.]*-fpm(\.service)?' | sed 's/\.service//' | sort -u | paste -sd " " - || true)
        if [ -n "$_php_svcs" ]; then 
            PHP_SVC_NAME="$_php_svcs"
        fi
    fi
}

# ------------------------------------------------------------------------------
# 6. DYNAMIC REAL-TIME POLLING
# ------------------------------------------------------------------------------
get_cpu_usage() {
    local u1 n1 s1 i1 io1 ir1 sir1 st1 _ u2 n2 s2 i2 io2 ir2 sir2 st2 _
    read -r _ u1 n1 s1 i1 io1 ir1 sir1 st1 _ < /proc/stat || true
    sleep 0.2
    read -r _ u2 n2 s2 i2 io2 ir2 sir2 st2 _ < /proc/stat || true
    
    local idled=$(( (i2 + io2) - (i1 + io1) ))
    local total1=$(( u1 + n1 + s1 + i1 + io1 + ir1 + sir1 + st1 ))
    local total2=$(( u2 + n2 + s2 + i2 + io2 + ir2 + sir2 + st2 ))
    local totald=$(( total2 - total1 ))
    
    if [ "$totald" -eq 0 ]; then 
        echo 0
    else 
        echo $(( (totald - idled) * 100 / totald ))
    fi
}

get_dynamic_info() {
    UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "Unknown")
    UPTIME="${UPTIME:0:22}"
    LOAD=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || echo "N/A")
    PROCS=$( (ps -e 2>/dev/null || true) | wc -l )
    CPU_P=$(get_cpu_usage || echo "0")

    if test -f /proc/meminfo; then
        local r_tot
        r_tot=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        r_tot="${r_tot//[^0-9]/}"
        
        local r_ava
        r_ava=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        r_ava="${r_ava//[^0-9]/}"
        
        RAM_T=$(( ${r_tot:-0} / 1024 ))
        local mem_avail=$(( ${r_ava:-0} / 1024 ))
        
        if [ "$mem_avail" -eq 0 ]; then
            local r_fre
            r_fre=$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
            r_fre="${r_fre//[^0-9]/}"
            
            local r_buf
            r_buf=$(awk '/^Buffers:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
            r_buf="${r_buf//[^0-9]/}"
            
            local r_cac
            r_cac=$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
            r_cac="${r_cac//[^0-9]/}"
            
            mem_avail=$(( (${r_fre:-0}/1024) + (${r_buf:-0}/1024) + (${r_cac:-0}/1024) ))
        fi
        
        RAM_U=$(( RAM_T - mem_avail ))
        if [ "$RAM_T" -gt 0 ]; then
            RAM_P=$(( RAM_U * 100 / RAM_T ))
        else
            RAM_P=0
        fi
        
        local s_tot
        s_tot=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        s_tot="${s_tot//[^0-9]/}"
        
        local s_fre
        s_fre=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        s_fre="${s_fre//[^0-9]/}"
        
        SWAP_T=$(( ${s_tot:-0} / 1024 ))
        SWAP_U=$(( SWAP_T - (${s_fre:-0} / 1024) ))
        if [ "$SWAP_T" -gt 0 ]; then
            SWAP_P=$(( SWAP_U * 100 / SWAP_T ))
        else
            SWAP_P=0
        fi
    else
        RAM_T=0; RAM_U=0; RAM_P=0; SWAP_T=0; SWAP_U=0; SWAP_P=0
    fi

    local d_info="" dt="0" du="0" dp="0"
    d_info=$(safe_cmd df -hP / 2>/dev/null | awk 'NR==2 {print $2, $3, $5}' || true)
    if [ -n "$d_info" ]; then 
        read -r dt du dp <<< "$d_info" || true
    fi
    DISK_T=${dt:-0}
    DISK_U=${du:-0}
    DISK_P=${dp//[^0-9]/}
    if [ -z "$DISK_P" ]; then 
        DISK_P=0
    fi
}

# ------------------------------------------------------------------------------
# 7. SERVICE & COMPONENT TRACKERS
# ------------------------------------------------------------------------------
check_daemon() {
    local bin="$1" ver="$2" daemons="$3"
    local is_installed=0
    local is_running=0

    if [[ "$bin" == "php-fpm" ]]; then
        if command -v php-fpm >/dev/null 2>&1; then 
            is_installed=1
        fi
        if [ "$daemons" != "php-fpm" ]; then 
            is_installed=1
        fi
    else
        for b in $bin $daemons; do
            if command -v "$b" >/dev/null 2>&1; then 
                is_installed=1
                break
            fi
        done
    fi

    if [ "$is_installed" -eq 1 ]; then
        if [ "$HAS_SYSTEMD" -eq 1 ]; then
            for d in $daemons; do
                if [ -n "$d" ]; then
                    if safe_cmd systemctl is-active --quiet "$d" 2>/dev/null; then 
                        is_running=1
                        break
                    fi
                fi
            done
        fi
        if [ "$is_running" -eq 0 ]; then
            if [[ "$bin" == "php-fpm" ]]; then
                if pgrep -f "php.*fpm.*master" >/dev/null 2>&1; then 
                    is_running=1
                fi
            else
                for b in $bin $daemons; do
                    if pgrep -x "$b" >/dev/null 2>&1; then 
                        is_running=1
                        break
                    fi
                done
            fi
        fi
    fi

    if [ "$is_installed" -eq 0 ]; then 
        echo "${GRAY}○ NOT INSTALLED${NC}"
    elif [ "$is_running" -eq 1 ]; then 
        echo "${GREEN}● RUNNING ${GRAY}$( if [ -n "$ver" ]; then echo "(v${ver})"; fi )${NC}"
    else 
        echo "${RED}○ OFFLINE ${GRAY}$( if [ -n "$ver" ]; then echo "(v${ver})"; fi )${NC}"
    fi
}

check_app() {
    local target="$1" ver="$2"
    local exists=0
    if [[ "$target" == /* ]]; then 
        if [ -e "$target" ]; then exists=1; fi
    else 
        if command -v "$target" >/dev/null 2>&1; then exists=1; fi
    fi

    if [ "$exists" -eq 1 ]; then 
        echo "${GREEN}● INSTALLED ${GRAY}$( if [ -n "$ver" ]; then echo "(v${ver})"; fi )${NC}"
    else 
        echo "${GRAY}○ NOT INSTALLED${NC}"
    fi
}

# ------------------------------------------------------------------------------
# 8. UI RENDERING ENGINE & DATA PARSERS (SRE ALIGNED)
# ------------------------------------------------------------------------------
draw_bar() {
    local perc="${1:-0}"
    perc="${perc//[^0-9]/}" 
    if [ -z "$perc" ]; then perc=0; fi
    if [ "$perc" -gt 100 ]; then perc=100; fi
    
    local alert_color=${2:-$WHITE}
    local filled=$(( perc * 40 / 100 ))
    local empty=$(( 40 - filled ))
    
    echo -ne "${alert_color}${B_O}${NC}"
    for ((i=0; i<filled; i++)); do echo -ne "${alert_color}#${NC}"; done
    for ((i=0; i<empty; i++)); do echo -ne "${GRAY}-${NC}"; done
    echo -ne "${alert_color}${B_C}${NC} ${BOLD}$(printf "%3s" "$perc")%${NC}"
}

print_2col_svc() {
    printf "      %-16s: %b" "$1" "$2"
    echo -ne "${COL_MID}${GRAY}│${NC} "
    printf "%-16s: %b\n" "$3" "$4"
}

draw_dashboard() {
    clear
    get_dynamic_info

    # --- ADVANCED METRICS GATHERING ---

    local S_NGINX=$(check_daemon nginx "$V_NGINX" "nginx")
    local S_MYSQL=$(check_daemon mysql "$V_MYSQL" "mysql mariadb mysqld")
    local S_REDIS=$(check_daemon redis-server "$V_REDIS" "redis redis-server")
    
    local php_label="PHP-FPM Engine"
    if [[ "$V_PHP" == *","* ]]; then php_label="PHP-FPM Pools"; fi
    local S_PHP=$(check_daemon php-fpm "$V_PHP" "$PHP_SVC_NAME")
    
    local S_PMA=$(check_app /usr/share/phpmyadmin "")
    local S_MEMC=$(check_daemon memcached "" "memcached")

    # SSL Dynamic Status Parser (Finds the cert with minimum days left)
    local CERT_COUNT=$( (ls -1d /etc/letsencrypt/live/*/ 2>/dev/null || true) | wc -l )
    local S_SSL="${GRAY}○ NOT INSTALLED${NC}"
    if [ "$CERT_COUNT" -gt 0 ]; then
        local min_days=999
        for pem in /etc/letsencrypt/live/*/cert.pem; do
            [ -e "$pem" ] || continue
            local exp_date=$(openssl x509 -enddate -noout -in "$pem" 2>/dev/null | cut -d= -f2 || true)
            if [ -n "$exp_date" ]; then
                local exp_sec=$(date -d "$exp_date" +%s 2>/dev/null || echo 0)
                local now_sec=$(date +%s)
                local days=$(( (exp_sec - now_sec) / 86400 ))
                [ "$days" -lt "$min_days" ] && min_days=$days
            fi
        done
        local renew_status="OFF"
        if safe_cmd systemctl is-active --quiet certbot.timer 2>/dev/null || grep -q 'certbot' /etc/crontab /etc/cron.*/* 2>/dev/null; then renew_status="ON"; fi
        
        local ssl_color=$GREEN
        if [ "$min_days" -le 15 ]; then ssl_color=$YELLOW; fi
        if [ "$min_days" -le 5 ]; then ssl_color=$RED; fi
        [ "$min_days" -eq 999 ] && min_days="?"
        
        S_SSL="${ssl_color}● OK ${GRAY}(${CERT_COUNT} certs | shortest: ${min_days} days | Auto: ${renew_status})${NC}"
    fi

    # Open Ports Fast Polling
    local OPEN_PORTS
    OPEN_PORTS=$(safe_cmd ss -tuln 2>/dev/null | awk 'NR>1 {print $5}' | awk -F':' '{print $NF}' | grep -Eo '^[0-9]+' | sort -nu | paste -sd "," - | cut -c 1-45 || true)
    [ -z "$OPEN_PORTS" ] && OPEN_PORTS="None"
    if [ "${#OPEN_PORTS}" -ge 45 ]; then OPEN_PORTS="${OPEN_PORTS}..."; fi

    local S_WP=$(check_app wp "$V_WP")
    local S_COMP=$(check_app composer "$V_COMP")
    local S_GIT=$(check_app git "$V_GIT")
    local S_NODE=$(check_app node "$V_NODE")

    # Security Modules
    local S_UFW="${GRAY}○ NOT INSTALLED${NC}"
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status
        if ufw_status=$(safe_cmd ufw status 2>/dev/null); then
            if echo "$ufw_status" | grep -qw active; then 
                local rule_count=$(echo "$ufw_status" | awk 'NR>4 && NF>0' | wc -l)
                S_UFW="${GREEN}● ACTIVE ${GRAY}(${rule_count} Rules)${NC}"
            else 
                S_UFW="${RED}○ INACTIVE${NC}"
            fi
        fi
    fi

    # 3-State SSH Hardening
    local S_SSH_HARD="${RED}● WEAK${GRAY} (Root Allowed)${NC}"
    if grep -qiE '^PermitRootLogin\s+no' /etc/ssh/sshd_config 2>/dev/null; then
        S_SSH_HARD="${GREEN}● HARDENED${GRAY} (Root Denied)${NC}"
    elif grep -qiE '^PermitRootLogin\s+prohibit-password' /etc/ssh/sshd_config 2>/dev/null; then
        S_SSH_HARD="${YELLOW}● MODERATE${GRAY} (Key Only)${NC}"
    fi

    local S_LOGGING="${RED}○ OFFLINE${NC}"
    if [ "$HAS_SYSTEMD" -eq 1 ]; then
        local log_ok=0
        safe_cmd systemctl is-active --quiet auditd 2>/dev/null && log_ok=$((log_ok + 1))
        safe_cmd systemctl is-active --quiet rsyslog 2>/dev/null && log_ok=$((log_ok + 1))
        safe_cmd systemctl is-active --quiet systemd-journald 2>/dev/null && log_ok=$((log_ok + 1))
        if [ "$log_ok" -ge 1 ]; then S_LOGGING="${GREEN}● Auditd/Syslog OK${NC}"; fi
    fi

    local S_F2B=$(check_daemon fail2ban-client "" "fail2ban")
    local S_CRON=$(check_daemon cron "" "cron crond")
    
    local S_BKP="${GRAY}○ NOT CONFIGURED${NC}"
    if [ -f "/var/log/bashboard_backup.log" ] || command -v borg >/dev/null 2>&1; then 
        S_BKP="${GREEN}✅ CONFIGURED${NC}"
    fi

    # --- UI RENDERING ---
    local r_fmt="      %-16s: ${WHITE}%-21s${NC}${COL_MID}${GRAY}│${NC} %-16s: ${WHITE}%-20s${NC}\n"

    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Server Time: %-20s${NC}\n" "BASHBOARD (V0.8)" "$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    echo -e "   📋 ${PURPLE}${BOLD}SERVER INFORMATION${NC}"
    printf "$r_fmt" "OS" "$OS" "Kernel" "$KERNEL"
    printf "$r_fmt" "Hostname" "$HOSTNAME" "Architecture" "$ARCH"
    printf "$r_fmt" "Public IP" "$PUBLIC_IP" "Local IP" "$LOCAL_IP"
    printf "$r_fmt" "Uptime" "$UPTIME" "Virtualization" "$VIRT"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    echo -e "   🏗️  ${PURPLE}${BOLD}SYSTEM RESOURCES${NC}"
    printf "      %-16s: ${WHITE}%-65s${NC}\n" "CPU Model" "$CPU_MODEL"
    printf "$r_fmt" "CPU Cores" "$CPU_CORES Cores" "Load Average" "$LOAD"
    printf "$r_fmt" "Total RAM" "${RAM_T} MB" "Active Procs" "$PROCS"
    printf "$r_fmt" "Total Disk" "$DISK_T" "Disk Type" "$DISK_TYPE"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    echo -e "   📊 ${PURPLE}${BOLD}RESOURCE UTILIZATION${NC}"
    
    local cpu_c=$WHITE; [ "$CPU_P" -ge 70 ] && cpu_c=$YELLOW; [ "$CPU_P" -ge 90 ] && cpu_c=$RED
    local ram_c=$WHITE; [ "$RAM_P" -ge 70 ] && ram_c=$YELLOW; [ "$RAM_P" -ge 90 ] && ram_c=$RED
    local swap_c=$WHITE; [ "$SWAP_P" -ge 30 ] && swap_c=$YELLOW; [ "$SWAP_P" -ge 60 ] && swap_c=$RED
    local disk_c=$WHITE; [ "$DISK_P" -ge 80 ] && disk_c=$YELLOW; [ "$DISK_P" -ge 90 ] && disk_c=$RED

    printf "      %-16s: " "CPU Usage" && draw_bar "$CPU_P" "$cpu_c" && echo ""
    printf "      %-16s: " "RAM Usage" && draw_bar "$RAM_P" "$ram_c" && printf "  (%s / %s MB)\n" "$RAM_U" "$RAM_T"
    printf "      %-16s: " "Swap Usage" && draw_bar "$SWAP_P" "$swap_c" && printf "  (%s / %s MB)\n" "$SWAP_U" "${SWAP_T:-0}"
    printf "      %-16s: " "Disk Usage" && draw_bar "$DISK_P" "$disk_c" && printf "  (%s / %s)\n" "$DISK_U" "$DISK_T"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    echo -e "   🌐 ${PURPLE}${BOLD}WEB, DATABASE & CACHE${NC}"
    print_2col_svc "Nginx Server" "$S_NGINX" "$php_label" "$S_PHP"
    print_2col_svc "MariaDB Server" "$S_MYSQL" "phpMyAdmin" "$S_PMA"
    print_2col_svc "Redis Server" "$S_REDIS" "Memcached" "$S_MEMC"
    printf "      %-16s: %b\n" "SSL Status" "$S_SSL"
    printf "      %-16s: ${WHITE}%s${NC}\n" "Open Ports" "$OPEN_PORTS"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    echo -e "   ⚙️  ${PURPLE}${BOLD}MANAGEMENT TOOLS${NC}"
    print_2col_svc "WP-CLI" "$S_WP" "Git Version" "$S_GIT"
    print_2col_svc "Composer" "$S_COMP" "Node.js Runtime" "$S_NODE"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    echo -e "   🔐 ${PURPLE}${BOLD}SECURITY & MAINTENANCE${NC}"
    print_2col_svc "UFW Firewall" "$S_UFW" "Fail2Ban" "$S_F2B"
    print_2col_svc "SSH Hardening" "$S_SSH_HARD" "Logging System" "$S_LOGGING"
    print_2col_svc "Cron Daemon" "$S_CRON" "Backup Status" "$S_BKP"
    
# --- STYLIZED FOOTER & ACTIONS ---
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ⚡ ${PURPLE}${BOLD}ACTIONS & OPERATIONS (Central Control Mode)${NC}\n"

    # 2-Column Sub-sections Layout
    echo -e "      🌐 ${WHITE}${BOLD}PROJECTS & SITES${NC}                           ${COL_MID}${GRAY}│${NC}  🛠️  ${WHITE}${BOLD}SYSTEM & STACK${NC}"
    echo -e "         ${GRAY}(Options coming soon...)${NC}                   ${COL_MID}${GRAY}│${NC}     ${GRAY}(Options coming soon...)${NC}"
    echo -e "                                               ${COL_MID}${GRAY}│${NC}"
    echo -e "      ⚙️  ${WHITE}${BOLD}SERVICE & SERVER CTRL${NC}                      ${COL_MID}${GRAY}│${NC}  🚨 ${WHITE}${BOLD}HEAVY MAINTENANCE${NC}"
    echo -e "         ${GRAY}(Options coming soon...)${NC}                   ${COL_MID}${GRAY}│${NC}     ${GRAY}(Options coming soon...)${NC}\n"
    
    echo -e "   ${GRAY}──────────────────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "   ${CYAN}(94)${NC} 🖥️  HTOP/TOP   ${CYAN}(93)${NC} 📜 LIVE LOGS   ${CYAN}(92)${NC} 🌐 NET-STAT   ${CYAN}(91)${NC} 🔄 REFRESH   ${RED}(90)${NC} ❌ EXIT"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# ------------------------------------------------------------------------------
# 9. MAIN APPLICATION LOOP (Clean UI Architecture)
# ------------------------------------------------------------------------------
get_static_info

while true; do
    draw_dashboard
    
    # Restore cursor for input reading
    tput cnorm 2>/dev/null || true
    echo -ne "\n   ${BOLD}${WHITE}Select an option:${NC} "
    
    read -r opt || opt="91"

    case "$opt" in
        90)
            echo -e "\n   ${GREEN}Detaching from SRE Console. Goodbye!${NC}\n"
            exit 0
            ;;
        91) 
            continue 
            ;;
        94)
            # HTOP / TOP Execution (Protected against set -e crash)
            trap 'true' INT
            if command -v htop >/dev/null 2>&1; then
                htop || true
            else
                top || true
            fi
            trap cleanup_env EXIT INT TERM
            continue
            ;;
        93)
            # LIVE LOGS Execution (Protected against set -e crash)
            trap 'true' INT
            echo -e "\n   ${YELLOW}>>> Tailing live system logs... Press [Ctrl+C] to return to Bashboard. <<<${NC}\n"
            if [ "$HAS_SYSTEMD" -eq 1 ] && command -v journalctl >/dev/null 2>&1; then
                journalctl -f -n 50 || true
            else
                tail -f /var/log/syslog /var/log/messages 2>/dev/null || true
            fi
            trap cleanup_env EXIT INT TERM
            continue
            ;;
        92)
            # NET-STAT Execution (Protected against set -e crash)
            trap 'true' INT
            echo -e "\n   ${YELLOW}>>> Live Network Ports & Connections... Press [Ctrl+C] to return. <<<${NC}\n"
            if command -v watch >/dev/null 2>&1; then
                watch -n 2 -t "ss -tupan | head -n 30" || true
            else
                ss -tupan | head -n 30 || true
                echo -ne "\n   ${GRAY}Press Enter to return...${NC}"
                read -r || true
            fi
            trap cleanup_env EXIT INT TERM
            continue
            ;;
        *)
            # Handling future module selections
            if [[ "$opt" =~ ^[0-9]+$ ]]; then
                echo -e "   ${YELLOW}Module ($opt) is currently under construction.${NC}"
                sleep 2
            else
                echo -e "   ${RED}Invalid Option! Please enter a valid number.${NC}"
                sleep 1
            fi
            continue
            ;;
    esac
done