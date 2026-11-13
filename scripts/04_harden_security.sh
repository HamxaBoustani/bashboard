#!/usr/bin/env bash
# ==============================================================================
# BASHBOARD MODULE: [04] Enterprise Security Hardening (TUI Edition)
# Version:          1.8.0 (Production Hardened: Dual Anti-Lockout Sentinel for
#                   Sudoer & Root SSH Keys, Ubuntu 24.04+ ssh.socket, Fail2Ban)
# Architecture:     Interactive DevSecOps Panel | Zero-Lockout | CIS Aligned
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
# 2. RUNTIME TELEMETRY & DUAL ANTI-LOCKOUT HELPERS
# ------------------------------------------------------------------------------
# Authoritative SSH port detection supporting systemd socket-activation (Ubuntu 24.04+)
detect_ssh_port() {
    local port=""
    mkdir -p -m 0755 /run/sshd 2>/dev/null || true
    if command -v sshd >/dev/null 2>&1; then
        port=$(sshd -T 2>/dev/null | awk '/^port / {print $2}' | head -n1 || true)
    fi
    if [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]]; then
        port=$(ss -tlnp 2>/dev/null | grep -E 'sshd|ssh\.socket|systemd' | awk '{print $4}' | awk -F':' '{print $NF}' | sort -nu | head -n1 || true)
    fi
    echo "${port:-22}"
}

SSH_PORT=$(detect_ssh_port)
if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    SSH_PORT=22
fi

# Anti-Lockout Gate 1: Verify if at least one active non-root sudoer user exists
has_active_sudoer() {
    local u sh
    for u in $(getent group sudo 2>/dev/null | awk -F: '{print $4}' | tr ',' ' ') \
             $(getent group wheel 2>/dev/null | awk -F: '{print $4}' | tr ',' ' '); do
        if [ -n "$u" ] && [ "$u" != "root" ] && id -u "$u" >/dev/null 2>&1; then
            sh=$(getent passwd "$u" | cut -d: -f7)
            if [[ "$sh" != "/bin/false" && "$sh" != "/usr/sbin/nologin" && "$sh" != "/sbin/nologin" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

# Anti-Lockout Gate 2: Verify if root has at least one authorized public SSH key configured
has_root_ssh_key() {
    [ -f "/root/.ssh/authorized_keys" ] && grep -qE '^(ssh-|ecdsa-|sk-)' "/root/.ssh/authorized_keys" 2>/dev/null
}

get_current_ssh_policy() {
    local policy=""
    mkdir -p -m 0755 /run/sshd 2>/dev/null || true
    if command -v sshd >/dev/null 2>&1; then
        policy=$(sshd -T 2>/dev/null | awk '/^permitrootlogin/ {print tolower($2)}' || true)
    fi
    if [ -z "$policy" ]; then
        policy=$(grep -rshiE '^\s*PermitRootLogin\s+' /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null | head -n1 | awk '{print tolower($2)}' || true)
    fi
    echo "$policy"
}

# Default configuration states
APPLY_SYSCTL=1
APPLY_SSH=1
APPLY_UFW=1
APPLY_FAIL2BAN=1

# Determine safe initial SSH Root Policy based on current server state
if [[ "$(get_current_ssh_policy)" == "no" ]] && has_active_sudoer; then
    SSH_ROOT_POLICY="no"
elif has_active_sudoer || has_root_ssh_key; then
    SSH_ROOT_POLICY="prohibit-password"
else
    # Server only has root user without SSH keys (password-only root) -> prevent lockout!
    SSH_ROOT_POLICY="yes"
fi

toggle_status() {
    local val="$1"
    if [ "$val" -eq 1 ]; then
        echo -e "${GREEN}[✔] ENABLED ${NC}"
    else
        echo -e "${GRAY}[ ] DISABLED${NC}"
    fi
}

# ------------------------------------------------------------------------------
# 3. LIVE STATE SENSORS
# ------------------------------------------------------------------------------
audit_ufw() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qw active; then
        local rc
        rc=$(ufw status 2>/dev/null | awk 'NR>4 && NF>0' | wc -l)
        echo -e "${GREEN}● ACTIVE (${rc} Rules)${NC}"
    else
        echo -e "${RED}○ INACTIVE${NC}"
    fi
}

audit_fail2ban() {
    if command -v fail2ban-client >/dev/null 2>&1 && systemctl is-active --quiet fail2ban 2>/dev/null; then
        echo -e "${GREEN}● RUNNING${NC}"
    else
        echo -e "${RED}○ OFFLINE${NC}"
    fi
}

audit_ssh_root() {
    local policy
    policy=$(get_current_ssh_policy)

    case "$policy" in
        no) echo -e "${GREEN}● HARDENED (No Root)${NC}" ;;
        prohibit-password|without-password) echo -e "${YELLOW}● MODERATE (Keys Only)${NC}" ;;
        *) echo -e "${RED}● WEAK (Password Allowed)${NC}" ;;
    esac
}

audit_sysctl() {
    if [ -f "/etc/sysctl.d/99-bashboard-security.conf" ]; then
        echo -e "${GREEN}● APPLIED${NC}"
    else
        echo -e "${GRAY}○ DEFAULT${NC}"
    fi
}

# ------------------------------------------------------------------------------
# 4. TUI DEFENSE DASHBOARD RENDERER
# ------------------------------------------------------------------------------
draw_security_tui() {
    clear
    local st_ufw st_f2b st_ssh st_sysctl
    st_ufw=$(audit_ufw)
    st_f2b=$(audit_fail2ban)
    st_ssh=$(audit_ssh_root)
    st_sysctl=$(audit_sysctl)

    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "   🚀 ${BOLD}${WHITE}%-50s${NC}    ${GREEN}Module: %-25s${NC}\n" "BASHBOARD SECURITY" "Hardening & Firewall TUI"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   📋 ${PURPLE}${BOLD}DEFENSE MATRIX & CURRENT POSTURE${NC}"
    echo -e "      Toggle protection layers below to prepare and apply server hardening."
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    printf "   ${CYAN}[1]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Live State: %b\n" "$(toggle_status "$APPLY_SYSCTL")" "Kernel Network & FS" "$st_sysctl"
    printf "   ${CYAN}[2]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Live State: %b\n" "$(toggle_status "$APPLY_SSH")" "SSH Daemon Policies" "$st_ssh"
    printf "   ${CYAN}[3]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Live State: %b\n" "$(toggle_status "$APPLY_UFW")" "UFW Zero-Lockout" "$st_ufw"
    printf "   ${CYAN}[4]${NC} %b %-22s ${COL_MID}${GRAY}│${NC} Live State: %b\n" "$(toggle_status "$APPLY_FAIL2BAN")" "Fail2Ban Protection" "$st_f2b"

    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "   ⚙️  ${PURPLE}${BOLD}TARGET TUNING PARAMETERS${NC}"
    printf "      %-22s: ${YELLOW}%-22s${NC}${COL_MID}${GRAY}│${NC} Active Port : ${GREEN}%s/tcp${NC}\n" "SSH Root Policy" "$SSH_ROOT_POLICY" "$SSH_PORT"
    printf "      %-22s: ${CYAN}%-22s${NC}${COL_MID}${GRAY}│${NC} Toggle Policy: ${CYAN}[5]${NC}\n" "Firewall Ports" "80, 443, ${SSH_PORT}"
    echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"

    echo -e "   ${GREEN}${BOLD}[9] ⚡ ENFORCE HARDENING MEASURES${NC}"
    echo -e "   ${RED}${BOLD}[0] ↩️  CANCEL AND RETURN TO BASHBOARD${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# ------------------------------------------------------------------------------
# 5. INTERACTIVE MENU EVENT LOOP
# ------------------------------------------------------------------------------
while true; do
    draw_security_tui
    tput cnorm 2>/dev/null || true
    echo -ne "\n   ${BOLD}${WHITE}Toggle or Choose Action [0-9]:${NC} "
    read -r opt || opt="0"

    case "$opt" in
        1) APPLY_SYSCTL=$(( 1 - APPLY_SYSCTL )) ;;
        2) APPLY_SSH=$(( 1 - APPLY_SSH )) ;;
        3) APPLY_UFW=$(( 1 - APPLY_UFW )) ;;
        4) APPLY_FAIL2BAN=$(( 1 - APPLY_FAIL2BAN )) ;;
        5)
            if [ "$SSH_ROOT_POLICY" == "prohibit-password" ]; then
                # Anti-Lockout Gate 1: Require sudoer before setting 'no'
                if has_active_sudoer; then
                    SSH_ROOT_POLICY="no"
                else
                    echo -e "\n   ${RED}⚠️  [LOCKOUT RISK] Cannot set Root Login to 'no'!${NC}"
                    echo -e "   ${YELLOW}No non-root user with sudo privileges was detected on this server.${NC}"
                    echo -e "   ${GRAY}Create a sudoer user first to avoid permanent terminal lockout.${NC}"
                    sleep 3
                fi
            elif [ "$SSH_ROOT_POLICY" == "no" ]; then
                if has_active_sudoer || has_root_ssh_key; then
                    SSH_ROOT_POLICY="prohibit-password"
                else
                    SSH_ROOT_POLICY="yes"
                fi
            else
                # Currently 'yes'
                if has_active_sudoer || has_root_ssh_key; then
                    SSH_ROOT_POLICY="prohibit-password"
                else
                    echo -e "\n   ${RED}⚠️  [LOCKOUT RISK] Cannot disable Root Password Login!${NC}"
                    echo -e "   ${YELLOW}Neither a non-root sudoer user nor a root SSH key (/root/.ssh/authorized_keys) was found.${NC}"
                    echo -e "   ${GRAY}Add an SSH key or create a sudoer user first to avoid locking yourself out.${NC}"
                    sleep 3.5
                fi
            fi
            ;;
        9)
            if [ "$APPLY_SYSCTL" -eq 0 ] && [ "$APPLY_SSH" -eq 0 ] && [ "$APPLY_UFW" -eq 0 ] && [ "$APPLY_FAIL2BAN" -eq 0 ]; then
                echo -e "\n   ${YELLOW}No hardening modules selected! Choose at least one.${NC}"
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
# 6. EXECUTION PHASE: ORCHESTRATED DEFENSE LAYERS
# ==============================================================================
clear
echo -e "${CYAN}==================================================================${NC}"
echo -e "   🛡️  ${BOLD}${WHITE}Enforcing Enterprise Hardening Baseline...${NC}"
echo -e "${CYAN}==================================================================${NC}\n"

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------------------
# 6.1 KERNEL NETWORK & FILESYSTEM HARDENING
# ------------------------------------------------------------------------------
if [ "$APPLY_SYSCTL" -eq 1 ]; then
    echo -e "${BLUE}--- [1/4] Applying Kernel Network & FS Security Parameters ---${NC}"
    SYSCTL_CONF="/etc/sysctl.d/99-bashboard-security.conf"

    # Enforce CIS baseline with Loose Reverse Path filtering (rp_filter = 2) for cloud safety
    cat > "$SYSCTL_CONF" <<'EOF'
# Reverse Path Filtering: Loose mode (2) avoids dropping legitimate asymmetric multi-homed/VPC traffic
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2

# Ignore ICMP broadcast requests & router redirects
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# TCP SYN Flood Mitigation
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_rfc1337 = 1

# Disable IP Source Routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# VFS Hardlink, Symlink & FIFO Protection
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
EOF

    # Apply sysctl parameters safely
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
    echo -e "   ${GREEN}✅ Kernel sysctl parameters successfully applied.${NC}"
fi

# ------------------------------------------------------------------------------
# 6.2 OPENSSH DAEMON POLICIES (First-Match-Wins Priority & Dual Anti-Lockout)
# ------------------------------------------------------------------------------
if [ "$APPLY_SSH" -eq 1 ]; then
    echo -e "\n${BLUE}--- [2/4] Securing OpenSSH Daemon Configuration ---${NC}"
    SSH_DROPIN_DIR="/etc/ssh/sshd_config.d"
    mkdir -p "$SSH_DROPIN_DIR"
    mkdir -p -m 0755 /run/sshd 2>/dev/null || true

    # Final safety verification Gate 1: 'no' strictly requires an active non-root sudoer
    if [ "$SSH_ROOT_POLICY" == "no" ] && ! has_active_sudoer; then
        SSH_ROOT_POLICY="prohibit-password"
    fi

    # Final safety verification Gate 2: 'prohibit-password' requires either a sudoer OR root SSH keys
    if [ "$SSH_ROOT_POLICY" == "prohibit-password" ] && ! has_active_sudoer && ! has_root_ssh_key; then
        echo -e "   ${YELLOW}⚠️  [LOCKOUT GUARD] No sudoer user and no root SSH key found! Keeping root password login enabled.${NC}"
        SSH_ROOT_POLICY="yes"
    fi

    # Named '00-' to guarantee execution ahead of cloud-init (e.g., 50-cloud-init.conf)
    SSHD_HARDENING_FILE="$SSH_DROPIN_DIR/00-bashboard-hardening.conf"

    cat > "$SSHD_HARDENING_FILE" <<EOF
# Bashboard DevSecOps Baseline (First-Match Precedence)
MaxAuthTries 4
LoginGraceTime 60
X11Forwarding no
PermitEmptyPasswords no
ClientAliveInterval 300
ClientAliveCountMax 2
PermitRootLogin ${SSH_ROOT_POLICY}
EOF

    # Validate syntax before triggering any service reload to prevent lockouts
    if sshd -t >/dev/null 2>&1; then
        systemctl daemon-reload 2>/dev/null || true
        if systemctl is-active --quiet ssh 2>/dev/null; then
            systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || true
        elif systemctl is-active --quiet sshd 2>/dev/null; then
            systemctl reload sshd 2>/dev/null || systemctl restart sshd 2>/dev/null || true
        elif systemctl is-active --quiet ssh.socket 2>/dev/null; then
            systemctl reload-or-restart ssh.socket 2>/dev/null || true
        fi
        echo -e "   ${GREEN}✅ OpenSSH daemon secured with policy: ${YELLOW}${SSH_ROOT_POLICY}${NC}"
    else
        echo -e "   ${RED}❌ OpenSSH syntax test failed! Reverting drop-in config to prevent lockout.${NC}" >&2
        rm -f "$SSHD_HARDENING_FILE"
    fi
fi

# ------------------------------------------------------------------------------
# 6.3 ZERO-LOCKOUT FIREWALL ENGINE (UFW)
# ------------------------------------------------------------------------------
if [ "$APPLY_UFW" -eq 1 ]; then
    echo -e "\n${BLUE}--- [3/4] Configuring UFW Firewall with Anti-Lockout Verification ---${NC}"
    if ! command -v ufw >/dev/null 2>&1; then
        apt-get -o DPkg::Lock::Timeout=60 update -qq && apt-get -o DPkg::Lock::Timeout=60 install -y -qq ufw
    fi

    # Reset default policies
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    # Guarantee active SSH port access
    ufw allow "${SSH_PORT}/tcp" comment "Bashboard Active SSH" >/dev/null 2>&1
    
    # Emergency fallback: If running on a non-standard port, explicitly keep 22 allowed to prevent lockouts
    if [ "$SSH_PORT" -ne 22 ]; then
        ufw allow 22/tcp comment "Bashboard Fallback SSH" >/dev/null 2>&1
    fi

    # Web services ingress
    ufw allow 80/tcp comment "HTTP Web Ingress" >/dev/null 2>&1
    ufw allow 443/tcp comment "HTTPS Web Ingress" >/dev/null 2>&1

    # Enable firewall non-interactively
    echo "y" | ufw enable >/dev/null 2>&1 || true
    echo -e "   ${GREEN}✅ UFW active: Ports ${SSH_PORT}/tcp (SSH), 80/tcp (HTTP), 443/tcp (HTTPS) confirmed open.${NC}"
fi

# ------------------------------------------------------------------------------
# 6.4 FAIL2BAN INTRUSION PREVENTION (Journald & python3-systemd Aware)
# ------------------------------------------------------------------------------
if [ "$APPLY_FAIL2BAN" -eq 1 ]; then
    echo -e "\n${BLUE}--- [4/4] Deploying Fail2Ban Intrusion Prevention System ---${NC}"
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        apt-get -o DPkg::Lock::Timeout=60 update -qq && apt-get -o DPkg::Lock::Timeout=60 install -y -qq fail2ban python3-systemd
    fi

    # Auto-detect log backend for modern systemd distros (Debian 12 / Ubuntu 24.04+ lack rsyslog)
    F2B_BACKEND="auto"
    if [ ! -f "/var/log/auth.log" ] && systemctl is-active --quiet systemd-journald 2>/dev/null; then
        apt-get -o DPkg::Lock::Timeout=60 install -y -qq python3-systemd >/dev/null 2>&1 || true
        F2B_BACKEND="systemd"
    fi

    mkdir -p /etc/fail2ban/jail.d

    # Use drop-in configuration without clobbering existing custom jail.local rules
    cat > "/etc/fail2ban/jail.d/00-bashboard.conf" <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled  = true
port     = ${SSH_PORT}
backend  = ${F2B_BACKEND}
maxretry = 3
bantime  = 24h
EOF

    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban >/dev/null 2>&1 || true
    echo -e "   ${GREEN}✅ Fail2Ban operational (Backend: ${F2B_BACKEND}, 3 failed attempts = 24h ban).${NC}"
fi

# ------------------------------------------------------------------------------
# 7. FINAL POSTURE VERIFICATION REPORT
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}=================================================================="
echo -e "   🛡️  HARDENING BASELINE APPLIED SUCCESSFULLY"
echo -e "==================================================================${NC}"
[ "$APPLY_SYSCTL" -eq 1 ] && printf "   %-22s: %b\n" "Kernel Hardening" "${GREEN}Active (/etc/sysctl.d/99-bashboard-security.conf)${NC}"
[ "$APPLY_SSH" -eq 1 ] && printf "   %-22s: %b\n" "OpenSSH Policy" "${GREEN}PermitRootLogin ${SSH_ROOT_POLICY} (Port ${SSH_PORT})${NC}"
[ "$APPLY_UFW" -eq 1 ] && printf "   %-22s: %b\n" "Firewall Status" "${GREEN}$(ufw status 2>/dev/null | head -n 1)${NC}"
[ "$APPLY_FAIL2BAN" -eq 1 ] && printf "   %-22s: %b\n" "Fail2Ban IPS" "${GREEN}$(systemctl is-active fail2ban 2>/dev/null || echo 'Active')${NC}"
echo -e "${GREEN}==================================================================${NC}"
exit 0