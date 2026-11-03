# 🚀 Bashboard: Lightweight Linux VPS Control Plane & Multi-Site Orchestrator

![Version](https://img.shields.io/badge/Version-1.6.2-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Ubuntu_22.04%20|%2024.04%20LTS%20|%20Debian_11%20|%2012-lightgrey.svg?logo=linux)
![Architecture](https://img.shields.io/badge/Architecture-Modular_Bash_TUI_%7C_Zero--Daemon-green.svg)
![Security](https://img.shields.io/badge/Security-POSIX_Isolated_%7C_Tenant_Sandboxing-red.svg)
![License](https://img.shields.io/badge/License-MIT-orange.svg)

**Bashboard** is a zero-overhead, modular terminal control plane and automation suite written in Bash. Engineered for standalone Linux VPS instances hosting multiple internal projects, agency client sites, or private eCommerce stores, Bashboard provides automated LEMP stack deployment, per-site on-demand PHP-FPM resource isolation, non-locking offsite backups to Google Drive, and automated Nginx virtual host management without running persistent background control panel daemons.

---

## 📌 Scope & Architectural Philosophy

### What Bashboard Is
* **A Zero-Daemon CLI/TUI Control Plane:** Bashboard executes purely within an active administrative SSH session. When closed, **zero management processes or control panel daemons remain in RAM**. All available hardware resources are dedicated to Nginx, MariaDB, Redis, and PHP-FPM.
* **A Blast-Radius Compartmentalizer:** Tailored for developer teams, agencies, and self-hosted server environments. If one WordPress site is compromised via a vulnerable plugin, POSIX permission boundaries and PHP sandboxing prevent lateral movement to neighboring virtual hosts or system credentials.
* **A Safe Operational Wrapper:** Replaces manual configuration steps with idempotent, rollback-aware Bash scripts that validate configurations (`nginx -t`, `php-fpm -t`) prior to triggering service reloads.

### What Bashboard Is Not
* **Not Public Shared Hosting Infrastructure:** Bashboard is not a drop-in replacement for CloudLinux, CageFS, or cPanel when hosting untrusted, hostile third-party users. It relies on standard Linux POSIX permissions and PHP-FPM pool isolation rather than kernel-level cgroups v2 resource virtualization or namespace chroot jails.

---

## 🏗️ System Architecture Topology

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
         Web Root: 755/644        Web Root: 755/644               │
         Temp: /site-a/tmp/       Temp: /site-b/tmp/              │
                │                        │                        │
       FastCGI Unix Socket      FastCGI Unix Socket               │
    /run/php/...-site_a.sock  /run/php/...-site_b.sock            │
                │                        │                        │
                ▼                        ▼                        │
        PHP-FPM Pool (A)         PHP-FPM Pool (B)                 │
        (pm = ondemand)          (pm = ondemand)                  │
        open_basedir Sandbox     open_basedir Sandbox             │
        Dynamic RAM Sizing       Dynamic RAM Sizing               │
        Slowlog: /logs/          Slowlog: /logs/                  │
                │                        │                        │
                └───────────┬────────────┘                        │
                            ▼                                     │
           MariaDB Server (Unix Socket / Isolated Users)          │
                            ▲                                     │
           Redis Object Cache (systemd supervised) ───────────────┘
```

---

## 📂 Repository Structure

```text
bashboard/
├── bashboard.sh                    # Core TUI Monitor, Status Loop & Dynamic Dispatcher
├── README.md                       # Systems Architecture & Operator Manual
└── scripts/                        # Modular Workload Engines
    ├── 01_install_lemp.sh          # [1] Dual-OS LEMP Provisioner (Sury Keyring / Ondrej PPA)
    ├── 02_create_vhost.sh          # [2] VHost Deployer (Hashed Tenants, Session Sandboxes, TLS)
    ├── 03_wordpress_manager.sh     # [3] WP Manager (WSOD Recovery & Tenant-Isolated Crontab)
    ├── 04_harden_security.sh       # [4] Security Hardening (Anti-Lockout SSH, UFW, Fail2Ban)
    ├── 06_log_optimizer.sh         # [6] Logrotate Optimizer (Dedicated Drop-ins & Journal Vacuum)
    ├── 07_delete_vhost.sh          # [7] Atomic 8-Tier Tenant Purge Engine (State Manifest Driven)
    └── 12_backup_gdrive.sh         # [12] Offsite Backup Engine (rclone Sync & Non-locking Dumps)
```

---

## 🚀 Modular Engine Details

### `[1]` LEMP Stack Provisioner (`01_install_lemp.sh`)
* **Dual-OS Repository Management:** Detects Debian vs. Ubuntu via `/etc/os-release`. Imports official Sury GPG keyrings on Debian (`packages.sury.org`) and Ondrej PPAs on Ubuntu.
* **Modernized PHP Runtime (7.4–8.5+):** Installs standard extensions while omitting deprecated packages (such as `xmlrpc`) to prevent APT dependency aborts.
* **Idempotent MariaDB Hardening:** Preserves native `unix_socket` authentication on modern MariaDB (10.4+) while optionally configuring root credentials without breaking administrative CLI access.
* **Task Logging:** Diverts raw command outputs to `/var/log/bashboard_lemp_install.log` while showing real-time `[OK]` status lines on the terminal.

### `[2]` Virtual Host & Tenant Provisioner (`02_create_vhost.sh`)
* **Collision-Resistant Tenant Identities:** Generates unprivileged tenant system users with an MD5-derived 4-character suffix (`v_${name}_${hash}`) and a system group with `/usr/sbin/nologin`, preventing 14-character truncation collisions and duplicate group errors.
* **Commercial Permissions Model:** Parent directory `/var/www/$DOMAIN` is set to `750` (`$vhost_user:www-data`), completely blocking neighboring tenants (`Other = ---`). Web payloads are owned by `$vhost_user:$vhost_user` with `FS_METHOD = 'direct'`, allowing native one-click plugin and core updates from the WordPress dashboard without FTP credential prompts.
* **Session & Temporary File Sandboxing:** Isolates temporary uploads and session data into `/var/www/$DOMAIN/tmp/` (`chmod 700`). Completely removes global `/tmp/` from `open_basedir`, locking the PHP process inside `/var/www/$DOMAIN/`, `/dev/urandom`, and `/usr/share/zoneinfo/`.
* **Realpath Cache Optimization:** Tunes `realpath_cache_size = 4096k` and `realpath_cache_ttl = 600` inside each pool to eliminate filesystem stat overhead associated with `open_basedir`.
* **Dynamic RAM Allocator & Rebalancer:** Calculates `pm.max_children` after reserving at least 20% of host RAM (min 1536MB) for MariaDB buffer pools, Redis, and the OS. Automatically rebalances all existing pools on creation or deletion, verified via `php-fpm -t` prior to reloading daemons.
* **Dedicated Logrotate Drop-ins:** Configures per-site drop-ins in `/etc/logrotate.d/vhost-$DOMAIN` using `su $vhost_user www-data` on `770` directories. Nginx logs rotate via zero-loss `USR1` signals; PHP slow logs rotate via `copytruncate`.
* **Atomic Rollback with Pre-existence Guard:** Traps runtime `ERR` signals; safely dismantles half-staged configurations if an error occurs, but preserves pre-existing databases.
* **Pre-Flight Let's Encrypt TLS Engine:** Queries public DNS-over-HTTPS (DoH) resolvers to verify that the public A-record points to the server's public IP prior to contacting ACME servers, preventing rate-limit lockouts. Falls back safely to self-signed TLS.

### `[3]` WordPress Site Manager (`03_wordpress_manager.sh`)
* **Tenant-Isolated System Crontab:** Disables web-triggered cron (`DISABLE_WP_CRON = true`) and installs an isolated `/etc/cron.d/` job running every 10 minutes strictly as the site's tenant user (`v_<id>`). Injects `HOME` and `WP_CLI_CACHE_DIR` to prevent `/nonexistent` directory creation aborts.
* **Privilege-Dropped WP-CLI:** Runs all WP-CLI operations strictly under the tenant's user identity using `runuser -u "$u"`, preventing rogue plugins from executing arbitrary code as root when an administrator opens the management console.
* **WSOD Recovery:** Deactivates faulty plugins via `wp plugin deactivate --all --skip-plugins`, bypassing fatal PHP errors that crash standard WP-CLI invocations.
* **Zero-Leak Debugging:** Toggling `WP_DEBUG` automatically configures `WP_DEBUG_LOG = true` and `WP_DEBUG_DISPLAY = false`, keeping stack traces and database credentials out of public HTML output.
* **Non-Locking Database Exports:** Streams MySQL dumps on-the-fly into `gzip` archives inside a root-restricted (`0700`) backup vault (`/var/backups/bashboard/`).

### `[4]` DevSecOps Hardening Engine (`04_harden_security.sh`)
* **Anti-Lockout Sudoer Sentinel:** Prohibits setting `PermitRootLogin no` unless at least one active non-root user in group `sudo` or `wheel` with a valid login shell is confirmed.
* **OpenSSH Drop-in Priority:** Deploys configurations as `/etc/ssh/sshd_config.d/00-bashboard-hardening.conf` to guarantee precedence under OpenSSH's first-match-wins rule.
* **Journald-Aware Fail2Ban:** Inspects the host logging system; automatically configures `backend = systemd` on modern Debian 12 and Ubuntu systems where `/var/log/auth.log` is absent.
* **Asymmetric-Safe Network Mitigations:** Sets `net.ipv4.conf.*.rp_filter = 2` (Loose mode) to protect against spoofing without dropping valid traffic in multi-homed or cloud VPC environments.

### `[6]` Log Rotation Optimizer (`06_log_optimizer.sh`)
* **Multi-Tenant Drop-in Synchronization:** Audits all active virtual hosts, ensures `/var/www/*/logs/` permissions are strictly `770` owned by `$vhost_user:www-data`, and synchronizes dedicated `/etc/logrotate.d/vhost-*` drop-ins.
* **Native Zero-Loss Rotation:** Nginx logs rotate with physical move and `USR1` signals; application slowlogs rotate via `copytruncate`, eliminating file descriptor deadlocks.
* **Journald Storage Ceiling:** Enforces hard caps (`SystemMaxUse=150M`) in `/etc/systemd/journald.conf.d/` and provides instant log vacuuming.

### `[7]` Virtual Host Purge Engine (`07_delete_vhost.sh`)
* **Manifest-Driven Database Discovery:** Reads `DB_NAME` and `DB_USER` from the root-owned `.bashboard-state` manifest, preventing broken regex drops or accidental database deletion.
* **Process-Locking Termination:** Dispatches graceful `SIGTERM` followed by forceful `SIGKILL` to all active tenant processes prior to calling `userdel`, completely preventing `user is currently used by process` deletion aborts.
* **Exact User & Group Eradication:** Verifies that the tenant username matches `^v_` and that the home path strictly equals `/var/www/$TARGET_SITE` before removing the account and group, protecting system users (such as `ubuntu` or `deploy`).
* **Post-Purge SRE Health Check:** Validates Nginx syntax (`nginx -t`) and tests all PHP-FPM binary configurations (`php-fpmX.Y -t`) to guarantee the server remains healthy after deletion.

### `[12]` Automated Google Drive Backup Engine (`12_backup_gdrive.sh`)
* **Non-Locking Dumps:** Runs `mysqldump` with `--single-transaction --quick --routines --triggers`, preventing table-locking stalls on live WooCommerce and transactional databases.
* **Offsite Cloud Streaming:** Compresses databases and web payloads on-the-fly and streams them to your configured Google Drive remote via `rclone`.
* **Automated Cloud Retention Pruning:** Automatically deletes remote backup snapshots older than your retention policy (default: 14 days) directly on Google Drive.
* **Nightly Automation:** Installs a cron drop-in in `/etc/cron.d/bashboard-gdrive-backup` running automatically at 03:00 AM.

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

## ☁️ Google Drive Backup Configuration Guide

Bashboard uses `rclone` for zero-overhead, off-site cloud backups.

### Step 1: Initialize rclone configuration
Run `rclone config` in your server terminal:
1. Enter `n` for a new remote.
2. Name the remote strictly: **`bashboard-gdrive`**
3. Storage type: enter `drive`
4. Leave `client_id` and `client_secret` blank (press Enter).
5. Scope: enter `1` (Full access to create/prune backup archives).
6. Leave `root_folder_id` and `service_account_file` blank.
7. Edit advanced config: enter `n`.
8. Remote configuration / web browser: enter `n` (headless mode).

### Step 2: Authorize Account
Execute the authorization command provided by rclone on a local machine with a browser (`rclone authorize "drive"`), or establish an SSH tunnel (`ssh -L 53682:127.0.0.1:53682 root@SERVER_IP`), authenticate with Google, and paste the generated JSON token into the server prompt.

### Step 3: Verify Connection
```bash
# Verify that the remote is connected and can query Google Drive:
rclone lsd bashboard-gdrive:
```

Once connected, launch Bashboard, choose option **`[12]`**, and press **`[8]`** to enable automated nightly backups.

---

## 📋 Recommended Operator Provisioning Workflow

When configuring a brand-new production node, follow this execution sequence:

```text
[Step 1] Option [1]  -> Provision LEMP Stack (Nginx, MariaDB, PHP-FPM, Redis, WP-CLI)
[Step 2] Option [4]  -> Enforce Security Hardening (UFW Firewall, Fail2Ban, Sysctl, SSH)
[Step 3] Option [2]  -> Deploy Virtual Host (Select WordPress or Blank, Isolated Tenant, SSL)
[Step 4] Option [3]  -> WordPress Manager (Offload WP-Cron, Verify Checksums, Flush Cache)
[Step 5] Option [6]  -> Log Optimizer (Synchronize dedicated drop-ins & Cap Journald)
[Step 6] Option [12] -> Configure Google Drive Backup (Enable nightly cloud sync)
```

---

## 🔍 Verification & Diagnostics Cheat Sheet

Verify your server's runtime health and security posture using these standard commands:

### 1. Verify Multi-Tenant POSIX Isolation (Lateral Movement Test)
Simulate a compromised tenant shell on Site B attempting to access Site A's configuration:
```bash
# Attempt to read Site A's database credentials as Site B's isolated user:
sudo -u v_site_b cat /var/www/site-a.com/public_html/wp-config.php

# Expected Output from Linux Kernel:
# cat: /var/www/site-a.com/public_html/wp-config.php: Permission denied
```

### 2. Verify True `open_basedir` Sandboxing (System Traversal Test)
Verify that PHP-FPM's `open_basedir` restriction blocks access to world-readable system files:
```bash
# Test that open_basedir blocks reading system files:
sudo -u v_example_com php -d open_basedir="/var/www/example.com/:/dev/urandom" -r "echo is_readable('/etc/passwd') ? 'LEAK' : 'BLOCKED';"

# Expected Output:
# BLOCKED
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

### 6. Verify Zero-Trust Upload Sandboxing
```bash
# Create a dummy test script in the uploads directory
echo "<?php phpinfo(); ?>" > /var/www/example.com/public_html/wp-content/uploads/test.php

# Request via curl (Must return 403 Forbidden or 404 Not Found, NEVER 200 OK)
curl -k -I https://example.com/wp-content/uploads/test.php

# Remove test script
rm -f /var/www/example.com/public_html/wp-content/uploads/test.php
```

### 7. Verify Tenant-Isolated WP-Cron Offloading
```bash
# Inspect the active system cron drop-in
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

# 3. If "111: Connection refused", test pool syntax for errors:
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