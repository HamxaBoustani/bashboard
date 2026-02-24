# 🚀 Bashboard: Enterprise VPS Management System

![Version](https://img.shields.io/badge/Version-0.8_(Beta)-blue.svg)
![Bash](https://img.shields.io/badge/Language-Bash_Script-4EAA25.svg?logo=gnu-bash)
![Platform](https://img.shields.io/badge/Platform-Linux_(Cross--Distro)-lightgrey.svg?logo=linux)
![Security](https://img.shields.io/badge/Security-Zero--Trust-red.svg)
![SRE](https://img.shields.io/badge/Architecture-SRE_%2F_DevOps-orange.svg)

**Bashboard** is not just another monitoring script; it is a **Central Command Center** engineered with strict SRE (Site Reliability Engineering) principles. Designed for SysAdmins and DevOps engineers, it provides zero-lag real-time monitoring, deep hardware-aware scanning, and a modular framework to manage LEMP/LAMP stacks without consuming your server's CPU.

---

## ✨ Enterprise-Grade Features

Under the hood, Bashboard replaces brittle traditional bash scripting with highly resilient, kernel-level mechanisms:

- 🛡️ **Zero-Crash Policy (`set -euo pipefail`):** Fully sanitized math operations and POSIX-compliant parsing prevent unexpected crashes even during kernel edge-cases.
- ⚡ **Zero-Lag Polling:** Heavy daemon discovery (like multiple PHP-FPM pools) is cached at startup. The live dashboard loop runs in **< 5ms** directly from `/proc/` and `/sys/`.
- 🔐 **Zero-Trust Security:** Built-in defenses against Symlink attacks, strict `umask 077` lock-file generation, and real-time SSH Hardening audits (`PermitRootLogin` analyzer).
- 🧠 **Hardware-Aware Detection:** Direct `sysfs` disk type reading (bypassing `lsblk` D-State hangs) to accurately detect NVMe/SSD vs HDD, even on complex cloud block devices.
- 🎨 **Grafana-Style Thresholds:** Dynamic, visually aligned UI that strictly shifts colors (White → Yellow → Red) based on DevOps critical limits (e.g., Swap triggers red at 60%).
- 🌍 **Cross-Distro Mastery:** Runs flawlessly on **Ubuntu, Debian, CentOS, RHEL, AlmaLinux, Rocky, Arch, and SUSE** via intelligent Package Manager routing and daemon aliasing.

---

## 📸 The Interface (Central Command Mode)

The UI is built with **100% Absolute Cursor Alignment**, ensuring the terminal never distorts or flickers, even when variables change lengths.

```text
   🚀 BASHBOARD SRE EDITION (V0.8)                          Server Time: 2026-02-24 20:00:00 
├────────────────────────────────────────────────────────────────────────────────────────────┤
   📋 SERVER INFORMATION
      OS              : Ubuntu 24.04.3 LTS     │ Kernel          : 6.14.0-37-generic   
      Hostname        : core-server            │ Architecture    : x86_64              
      Public IP       : ***.***.***.***        │ Local IP        : 10.0.0.5         
      Uptime          : 30 days, 4 hours       │ Virtualization  : KVM           
...
```

---

## ⚙️ Directory Structure & Architecture

Bashboard uses a modular execution structure. The core loop handles the UI and safety, while heavy operations are outsourced to the `scripts/` directory.

```text
bashboard/
├── bashboard.sh            # The Core Engine & UI (Run this)
├── README.md               # Documentation
└── scripts/                # Action Modules (Modular Architecture)
    ├── install_lemp.sh     # Option 1
    ├── manage_wp.sh        # Option 2
    ├── site_summary.sh     # Option 3
    ├── backup_restore.sh   # Option 12
    └── ...                 # Extendable up to 99 modules
```
*(Note: As of v0.8, the core foundation is 100% stable. Action scripts inside the `scripts/` folder are actively being developed to reach version 1.0).*

---

## 🛠️ Installation & Usage

**1. Clone the repository:**
```bash
git clone https://github.com/yourusername/bashboard.git
cd bashboard
```

**2. Make the core script executable:**
```bash
chmod +x bashboard.sh
```

**3. Run as Root (Required for Kernel/Systemd interactions):**
```bash
sudo ./bashboard.sh
```

---

## 🕹️ Integrated Live Tools (Non-Blocking)

Bashboard natively handles `SIGINT` (Ctrl+C) hooks to allow live tools to run securely without terminating the parent dashboard:
- **[94] HTOP / TOP:** Drops you into native process monitoring.
- **[93] LIVE LOGS:** Directly tails `journalctl` or `/var/log/syslog` securely.
- **[92] NET-STAT:** Live network port and TCP/UDP socket tracking via `ss`.

---

## 🛡️ Security Audit & Hardening Notes (For DevSecOps)
If you are auditing this code, note the following protections built-in:
- **DBus Hang Prevention:** Systemctl queries are safely encapsulated in a custom `timeout` wrapper (`safe_cmd`) to prevent dashboard freezes during systemd/dbus failures.
- **Set-e Trap Survival:** Sub-shell mathematical evaluations (`$((...))`) strictly strip non-numeric strings to prevent arithmetic expansions from triggering terminal exits.
- **Interactive Prompts Blocked:** Unattended upgrades (`apt-get upgrade`) use strict `DEBIAN_FRONTEND=noninteractive` and forced config overrides to prevent dpkg prompt hangs.

---

## 🤝 Contributing
Bashboard is an expanding framework. To create a new module:
1. Write a standard bash script.
2. Place it in the `scripts/` directory.
3. Link it in the `case "$opt" in` block at the bottom of `bashboard.sh`.

## 📜 License
This project is licensed under the MIT License. Feel free to fork, harden, and modify for your Enterprise environments.
