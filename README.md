# 🚀 Bashboard: Enterprise Linux VPS Control Plane & WordPress Orchestrator

![Version](https://img.shields.io/badge/Version-1.6.2_(Production_Hardened)-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Ubuntu_22.04%20|%2024.04%20LTS%20|%20Debian_11%20|%2012-lightgrey.svg?logo=linux)
![Architecture](https://img.shields.io/badge/Architecture-Modular_TUI_%7C_Zero--Daemon-green.svg)
![Security](https://img.shields.io/badge/Security-POSIX_Sandbox_%7C_sys__temp__dir_%7C_750_Isolation-red.svg)
![License](https://img.shields.io/badge/License-MIT-orange.svg)

**Bashboard** is a resilient, zero-overhead terminal control plane and systems automation engine engineered strictly in Bash under **Site Reliability Engineering (SRE)** and **DevSecOps** standards. Designed for standalone production Linux VPS instances, Bashboard provisions high-performance LEMP stacks, isolates multi-tenant workloads via unprivileged POSIX users, sandboxes PHP temporary files and sessions away from global `/tmp`, enforces parent-directory isolation that allows native one-click WordPress dashboard updates without FTP prompts, dynamically rebalances PHP-FPM pools to prevent OOM panics, and streams automated non-locking database backups directly to **Google Drive** without running background daemons or web control panels.

---

## ⚡ Why Bashboard? (Zero-Daemon Architecture)

Traditional server control panels (cPanel, Plesk, aaPanel, CyberPanel) run persistent Node.js, Python, or Go daemons that permanently consume 500MB–1.5GB of RAM and expose additional attack surfaces.

Bashboard operates under a **Zero-Daemon Philosophy**:
* **0 MB Idle Footprint:** Bashboard runs purely in your active SSH terminal session. Once exited, **zero** management daemons or background processes remain. 100% of server RAM is dedicated to Nginx, MariaDB, and your application workloads.
* **Kernel-Level Atomic Locking:** Enforces non-blocking `flock` on File Descriptor 200 over `/run/bashboard.lock`. Lock release is guaranteed by the Linux kernel upon process death (even under uncatchable `SIGKILL`), eliminating stale lock directories common to fragile scripts.
* **Accurate & Non-Forking Telemetry:** Samples `/proc/stat` via an exact 100ms $\Delta t$ Jiffy delta for precise multi-core CPU metrics and parses `/proc/meminfo` via a pure Bash `while read` loop, avoiding process storms and dangerous `eval` injection vectors.
* **Commercial Multi-Tenant POSIX Model:** Each tenant operates under an isolated unprivileged system user (`v_<id>`). Parent directories are locked down with `750` permissions (`$vhost_user:www-data`), completely eliminating horizontal cross-tenant data leaks while enabling native dashboard-based WordPress updates.

---

## 🏗️ Multi-Tenant Infrastructure Topology

```text
                                [ Public Internet ]
                                         │
                         ┌───────────────┴───────────────┐
                         │  UFW Firewall (Port 80 / 443) │
                         └───────────────┬───────────────┘
                                         ▼
                                Nginx Reverse Proxy
                     (HTTP/2 | TLS 1.3 | Zero-Trust Uploads)
                                         │
                ┌────────────────────────┼────────────────────────┐
                ▼                        ▼                        ▼
      [ VHost: site-a.com ]    [ VHost: site-b.com ]    [ VHost: uploads.site-a ]
         (User: v_site_a)         (User: v_site_b)       (Static Assets Only)
         Parent Dir: 750          Parent Dir: 750        (PHP Execution DENIED)
         Web Root: Direct         Web Root: Direct                │
         Temp: /site-a/tmp/       Temp: /site-b/tmp/              │
                │                        │                        │
       FastCGI Unix Socket      FastCGI Unix Socket               │
    /run/php/...-site_a.sock  /run/php/...-site_b.sock            │
                │                        │                        │
                ▼                        ▼                        │
        PHP-FPM Pool (A)         PHP-FPM Pool (B)                 │
        (pm = ondemand)          (pm = ondemand)                  │
        sys_temp_dir Sandboxed   sys_temp_dir Sandboxed           │
        Dynamic SRE Rebalancer   Dynamic SRE Rebalancer           │
        Slowlog: /logs/          Slowlog: /logs/                  │
                │                        │                        │
                └───────────┬────────────┘                        │
                            ▼                                     │
           MariaDB Server (Unix Socket / Isolated Users)          │
                            ▲                                     │
           Redis Object Cache (systemd supervised) ───────────────┘
```

---

## 📂 Project Structure

```text
bashboard/
├── bashboard.sh                    # Core TUI Monitor, Status Loop & Dynamic Dispatcher
├── README.md                       # Comprehensive Technical Architecture & Operator Manual
└── scripts/                        # Modular Workload Execution Engines
    ├── 01_install_lemp.sh          # [1] Dual-OS LEMP Provisioner (Ondrej PPA / Sury Keyring)
    ├── 02_create_vhost.sh          # [2] VHost Deployer (Session Sandboxing, SRE Rebalance, SSL)
    ├── 03_wordpress_manager.sh     # [3] WP Manager (WSOD Recovery & Tenant Crontab Offloader)
    ├── 04_harden_security.sh       # [4] DevSecOps Hardening (Anti-Lockout SSH, UFW, Fail2Ban)
    ├── 06_log_optimizer.sh         # [6] Logrotate Engine (Dedicated Drop-ins & Journal Vacuum)
    ├── 07_delete_vhost.sh          # [7] Atomic 8-Tier Tenant Purge Engine (User & Pool Purge)
    └── 12_backup_gdrive.sh         # [12] Off-site Google Drive Backup (rclone & Non-locking Dump)
```

---

## 🚀 Built-In Modular Engines Breakdown

### `[1]` LEMP Stack Provisioner (`01_install_lemp.sh`)
* **Dual-OS Repository Routing:** Detects Debian vs. Ubuntu cleanly via `/etc/os-release`. Deploys official Sury GPG keyrings on Debian (`packages.sury.org`) and Ondrej PPAs on Ubuntu, preventing package manager breakage.
* **Modernized PHP Runtime (7.4–8.5+):** Installs standard enterprise extensions while stripping deprecated modules (such as `xmlrpc`) to eliminate APT dependency aborts.
* **Idempotent MariaDB Hardening:** Preserves native `unix_socket` authentication on modern MariaDB (10.4+) while optionally configuring administrative passwords without breaking automated scripts.
* **Structured System Task Logger:** Channels full command output to `/var/log/bashboard_lemp_install.log` while displaying clean console status indicators.

### `[2]` Virtual Host & Tenant Provisioner (`02_create_vhost.sh`)
* **Unique Hashed Tenant Users:** Creates unprivileged tenant users with a 4-character MD5 hash (`v_${name}_${hash}`) and groups with `/usr/sbin/nologin`, completely eliminating 14-character truncation collisions and duplicate group crashes (`exit code 9`).
* **Cross-Tenant Session & Temp Sandboxing:** Isolates temporary uploads and session data into `/var/www/$DOMAIN/tmp/` with `chmod 700`. Completely removes global `/tmp/` from `open_basedir`, locking PHP within `/var/www/$DOMAIN/`, `/dev/urandom`, and `/usr/share/zoneinfo/`.
* **Realpath Cache Performance Tuning:** Injects `realpath_cache_size = 4096k` and `realpath_cache_ttl = 600` into each tenant pool, completely neutralizing the filesystem stat overhead of `open_basedir`.
* **Commercial-Grade Permissions Model:** Parent directory `/var/www/$DOMAIN` is locked down with `750` permissions (`$vhost_user:www-data`), barring access to other tenants (`Other = ---`). Web payload is owned by `$vhost_user:$vhost_user` with `FS_METHOD = 'direct'`, allowing seamless one-click plugin/theme updates and core updates from the WordPress dashboard without FTP prompts.
* **Runtime SRE Memory Rebalancer:** Dynamically allocates `pm.max_children` after reserving at least 20% of host RAM (min 1536MB) for MariaDB buffer pools, Redis, and OS operations. Automatically rebalances all existing pools on creation and deletion, guarded by a PHP-FPM syntax test gate before calling `reload`.
* **Tenant-Dedicated Logrotate Drop-ins:** Deploys individual configurations to `/etc/logrotate.d/vhost-$DOMAIN` with directory permissions `770` owned by `$vhost_user:www-data`, completely solving wildcard logrotate permission deadlocks. Nginx logs rotate via zero-loss `USR1` signals; PHP slow logs rotate via `copytruncate` under tenant identity.
* **SRE Atomic Rollback Trap with Pre-existence Guard:** Traps any runtime `ERR` signal during deployment; purges partially staged configs and unbinds pools, but preserves pre-existing databases.
* **Pre-Flight Let's Encrypt TLS Engine:** Queries public DNS-over-HTTPS (DoH) resolvers to verify that the public A-record matches the server's public IP before contacting ACME servers, preventing 5-attempt rate-limit lockouts.

### `[3]` WordPress Site Manager (`03_wordpress_manager.sh`)
* **Tenant-Isolated Linux Crontab:** Disables web-triggered cron (`DISABLE_WP_CRON = true`) and installs an isolated `/etc/cron.d/` job executing every 10 minutes strictly as the site's tenant user (`v_<id>`). Injects `HOME` and `WP_CLI_CACHE_DIR=/tmp/wp-cache-$id` to eliminate `/nonexistent` directory creation warnings.
* **Privilege-Dropped WP-CLI:** Runs all WP-CLI commands strictly as the tenant user using `runuser -u "$u"`, preventing compromised plugins from executing arbitrary code as root when an administrator views the management dashboard.
* **Bulletproof WSOD Recovery:** Deactivates rogue plugins via `wp plugin deactivate --all --skip-plugins`, bypassing fatal PHP errors that crash standard WP-CLI calls.
* **Zero-Leak Debugging:** Toggling `WP_DEBUG` automatically enforces `WP_DEBUG_LOG = true` and `WP_DEBUG_DISPLAY = false` to prevent leaking server paths and database credentials to visitors.
* **Hardened Database Exports:** Streams MySQL dumps on-the-fly into `gzip` archives inside a root-restricted (`0700`) backup vault (`/var/backups/bashboard/`).

### `[4]` DevSecOps Hardening Engine (`04_harden_security.sh`)
* **Anti-Lockout Sudoer Sentinel:** Prohibits setting `PermitRootLogin no` unless at least one active non-root user in group `sudo` or `wheel` with a valid shell is detected on the system.
* **OpenSSH Drop-in Priority:** Deploys configurations as `/etc/ssh/sshd_config.d/00-bashboard-hardening.conf` to guarantee precedence under OpenSSH's first-match-wins rule.
* **Journald-Aware Fail2Ban:** Inspects the host logging system; automatically configures `backend = systemd` on modern Debian 12 and Ubuntu systems where `/var/log/auth.log` is absent.
* **Asymmetric-Safe Network Mitigations:** Sets `net.ipv4.conf.*.rp_filter = 2` (Loose mode) to protect against spoofing without dropping valid traffic in multi-homed or cloud VPC environments.

### `[6]` Log Rotation Optimizer (`06_log_optimizer.sh`)
* **Multi-Tenant Drop-in Synchronization:** Audits all active virtual hosts, ensures `/var/www/*/logs/` permissions are strictly `770` owned by `$vhost_user:www-data`, and synchronizes dedicated `/etc/logrotate.d/vhost-*` drop-ins.
* **Native Zero-Loss Rotation:** Nginx logs rotate with physical move and `USR1` signal; application slowlogs rotate via `copytruncate`, eliminating file descriptor deadlocks and PHP-FPM permission crashes.
* **Accurate Retention Calculus:** Correctly calculates daily vs. weekly rotation cycles before purging dead-weight `.gz` archives, preserving historical logs.
* **Journald Storage Ceiling:** Enforces hard caps (`SystemMaxUse=150M`) in `/etc/systemd/journald.conf.d/` and provides instant log vacuuming.

### `[7]` Virtual Host Purge Engine (`07_delete_vhost.sh`)
* **Manifest-Driven Database Discovery:** Reads `DB_NAME` and `DB_USER` from the immutable root-owned `.bashboard-state` manifest, preventing malicious or broken regex SQL injections.
* **Process-Locking Termination:** Dispatches graceful `SIGTERM` followed by forceful `SIGKILL` to all active tenant processes prior to calling `userdel`, completely preventing `user is currently used by process` deletion aborts.
* **Atomic 8-Tier Destruction:** Dismantles Nginx configs, revokes Certbot certificates, purges dedicated logrotate drop-ins, removes tenant system users AND primary groups, purges system crontabs, removes `/etc/hosts` entries, drops databases/users, and cleans web payloads and temp sandboxes.
* **Runtime Memory Reclamation & Rebalance Gate:** Recalculates and rebalances `pm.max_children` across all remaining active pools after running syntax validation, distributing reclaimed RAM to active sites with zero downtime.

### `[12]` Automated Google Drive Backup Engine (`12_backup_gdrive.sh`)
* **Zero-Locking WooCommerce-Safe Dumps:** Dumps MySQL databases using `--single-transaction --quick --routines --triggers`, preventing checkout stalls or database table-locking outages on live e-commerce stores.
* **Off-Site Cloud Streaming:** Compresses databases and web payloads on-the-fly and streams them to your configured Google Drive remote via `rclone`.
* **Automated Cloud Retention Pruning:** Deletes remote backup snapshots older than your retention policy (e.g., 14 days) directly on Google Drive, eliminating cloud storage overage.
* **Nightly Automation:** Installs a non-intrusive system crontab in `/etc/cron.d/` running automatically at 03:00 AM.

---

## 🛠️ Installation & Quickstart

### System Requirements
* **Operating System:** Ubuntu 22.04 / 24.04 LTS or Debian 11 / 12
* **Privileges:** Root access (`sudo -i`)
* **Terminal Geometry:** 95+ Columns recommended

```bash
# 1. Clone the repository into /opt/
cd /opt
git clone https://github.com/yourusername/bashboard.git
cd bashboard

# 2. Grant administrative execution permissions across the suite
chmod 700 bashboard.sh scripts/*.sh
chown -R root:root /opt/bashboard

# 3. Launch Bashboard Control Engine
./bashboard.sh
```

---

## 📋 Recommended Operator Provisioning Workflow

When bringing up a brand-new production node, follow this execution sequence:

```text
[Step 1] Option [1]  -> Provision LEMP Stack (Nginx, MariaDB, PHP-FPM, Redis, WP-CLI)
[Step 2] Option [4]  -> Enforce Security Hardening (UFW Firewall, Fail2Ban, Sysctl, SSH)
[Step 3] Option [2]  -> Deploy Virtual Host (Select WordPress or Blank, Isolated Tenant, SSL)
[Step 4] Option [3]  -> WordPress Manager (Offload WP-Cron, Verify Checksums, Flush Cache)
[Step 5] Option [6]  -> Log Optimizer (Synchronize dedicated drop-ins & Cap Journald)
[Step 6] Option [12] -> Configure Google Drive Backup (Automate nightly off-site snapshots)
```

---

## 🔍 Verification & Diagnostics Cheat Sheet

As a systems engineer, verify your server's runtime health and security posture using these standard commands:

### 1. Verify Multi-Tenant POSIX Isolation (Lateral Movement Test)
Simulate a compromised tenant shell on Site B attempting to access Site A's configuration:
```bash
# Attempt to read Site A's database credentials as Site B's isolated user:
sudo -u v_site_b cat /var/www/site-a.com/public_html/wp-config.php

# Expected Output from Linux Kernel:
# cat: /var/www/site-a.com/public_html/wp-config.php: Permission denied
```

### 2. Verify True `open_basedir` Sandboxing (System Traversal Test)
Execute an explicit test verifying that PHP-FPM's `open_basedir` restriction blocks access to world-readable system files:
```bash
# Test that open_basedir successfully blocks reading /etc/passwd:
sudo -u v_example_com php -d open_basedir="/var/www/example.com/:/tmp/wp-cache-example_com/" -r "echo is_readable('/etc/passwd') ? 'LEAK' : 'BLOCKED';"

# Expected Output:
# BLOCKED (open_basedir restriction in effect)
```

### 3. Verify Cross-Tenant Temporary & Session Sandboxing
```bash
# Verify that the tenant's temp sandbox is locked down to mode 700:
ls -ld /var/www/example.com/tmp
# Must show: drwx------ v_example_com v_example_com
```

### 4. Verify One-Click WordPress Dashboard Operations
```bash
# Verify that the web payload is owned by the tenant user, with parent isolated:
ls -ld /var/www/example.com
# Must show: drwxr-x--- v_example_com www-data

ls -la /var/www/example.com/public_html
# Must show: -rw-r--r-- 1 v_example_com v_example_com ...
```

### 5. Inspect Isolated PHP-FPM Pools & Sockets
```bash
# Verify physical creation of dedicated pool sockets
ls -la /run/php/php*-fpm-*.sock

# Test pool syntax across all installed PHP versions
for fpm in /usr/sbin/php-fpm*; do "$fpm" -t; done
```

### 6. Verify Tenant-Isolated WP-Cron Offloading
```bash
# Inspect the active system cron drop-in (Must show execution under tenant identity with HOME and WP_CLI_CACHE_DIR)
cat /etc/cron.d/bashboard-wp-*

# Run cron event manually as tenant user to verify zero permission conflicts:
sudo -u v_example_com HOME=/var/www/example.com WP_CLI_CACHE_DIR=/tmp/test-cache php /usr/local/bin/wp cron event list --path=/var/www/example.com/public_html
```

---

## 🚨 Troubleshooting & Disaster Recovery

### 1. 502 Bad Gateway Outage
If Nginx responds with `502 Bad Gateway`, check:
```bash
# 1. Tail the virtual host's dedicated error log
tail -n 20 /var/www/example.com/logs/nginx_error.log

# 2. Check if the dedicated PHP-FPM socket exists and has correct permissions
ls -la /run/php/php*-fpm-example_com.sock
# Must show: srw-rw---- 1 www-data www-data

# 3. If "111: Connection refused", check if PHP-FPM failed syntax due to an orphaned pool:
sudo /usr/sbin/php-fpm$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;') -t
```

### 2. PHP-FPM Service Crash (`status=78`)
If PHP-FPM exits with status 78, it indicates an invalid pool configuration (commonly an orphaned slowlog path from a manually deleted site):
```bash
# Test configurations to reveal the offending file and line number
sudo php-fpm8.3 -t 2>/dev/null || sudo php-fpm8.4 -t 2>/dev/null

# Clean up orphaned configurations safely
sudo rm -f /etc/php/*/fpm/pool.d/orphaned_site.conf
sudo systemctl restart "php*-fpm"
```

### 3. WordPress White Screen of Death (WSOD)
If a plugin update or fatal error brings down WordPress:
1. Launch Bashboard: `./bashboard.sh`
2. Select **`[3] WordPress Manager`** -> Choose the target domain.
3. Select **`[6] 🚨 Deactivate ALL Plugins (WSOD Fix)`**.
4. The system executes `wp plugin deactivate --all --skip-plugins`, bypassing fatal errors and restoring site availability instantly.

---

## 🤝 Contributing & Extending Modules

1. Fork the repository.
2. Add your custom task script into `scripts/` following the naming standard: `scripts/XX_module_name.sh`.
3. Ensure strict mode compliance: start scripts with `set -euo pipefail`.
4. Ensure scripts are idempotent, non-interactive, and trap runtime errors.
5. Submit a Pull Request.

---

## 📜 License
This project is licensed under the **MIT License**. Engineered for production use on bare-metal and cloud VPS nodes.