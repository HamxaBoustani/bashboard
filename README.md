# 🚀 Bashboard: Lightweight Linux VPS Control Plane & Multi-Site Orchestrator

![Version](https://img.shields.io/badge/Version-1.8.0-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Ubuntu_22.04%20|%2024.04%20|%2026.04_LTS%20|%20Debian_11%20|%2012-lightgrey.svg?logo=linux)
![Architecture](https://img.shields.io/badge/Architecture-Modular_Bash_TUI_%7C_Zero--Daemon-green.svg)
![Security](https://img.shields.io/badge/Security-POSIX_Isolated_%7C_Syscall_Locked-red.svg)
![License](https://img.shields.io/badge/License-MIT-orange.svg)

**Bashboard** is a zero-overhead, modular terminal control plane and automation suite written in Bash. Engineered for standalone Linux VPS instances hosting multiple internal projects, agency client sites, or private eCommerce stores, Bashboard provides automated LEMP stack deployment, per-site on-demand PHP-FPM resource isolation, non-locking offsite backups to Google Drive, and automated Nginx virtual host management without running persistent background control panel daemons.

---

## 📌 Scope & Architectural Philosophy

### What Bashboard Is
* **A Zero-Daemon CLI/TUI Control Plane:** Bashboard executes purely within an active administrative SSH session. When closed, **zero management processes or control panel daemons remain in RAM**. All available hardware resources are dedicated to Nginx, MariaDB, Redis, and PHP-FPM.
* **A Blast-Radius Compartmentalizer:** Tailored for developer teams, agencies, and self-hosted server environments. If one WordPress site is compromised via a vulnerable plugin, POSIX permission boundaries (`0750`), PHP filesystem sandboxing (`open_basedir`), and kernel syscall restrictions (`disable_functions`) prevent lateral movement to neighboring virtual hosts or system files.
* **A Safe Operational Wrapper:** Replaces error-prone manual configuration with idempotent, rollback-aware Bash scripts that validate syntax (`nginx -t`, `php-fpm -t`, `sshd -t`, `logrotate -d`) prior to triggering service reloads.

### What Bashboard Is Not
* **Not Public Shared Hosting Infrastructure:** Bashboard is not a drop-in replacement for CloudLinux, CageFS, or cPanel when hosting untrusted, hostile third-party users. It relies on standard Linux POSIX permissions and PHP-FPM pool isolation rather than kernel-level `cgroups v2` resource virtualization or namespace `chroot` jails.

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
                 (HTTP/2 | TLS 1.3 | Cloudflare Real-IP | Rate-Limited)
                                         │
                ┌────────────────────────┼────────────────────────┐
                ▼                        ▼                        ▼
      [ VHost: site-a.com ]    [ VHost: site-b.com ]    [ VHost: uploads.site-a ]
       (User: v_site_a_xxxx)    (User: v_site_b_yyyy)     (Static Assets Only)
         Parent Dir: 750          Parent Dir: 750        (PHP Execution DENIED)
         Web Root: 755/644        Web Root: 755/644               │
         wp-config: 600           wp-config: 600                  │
         Temp: /site-a/tmp/       Temp: /site-b/tmp/              │
                │                        │                        │
       FastCGI Unix Socket      FastCGI Unix Socket               │
    /run/php/...-site_a.sock  /run/php/...-site_b.sock            │
                │                        │                        │
                ▼                        ▼                        │
        PHP-FPM Pool (A)         PHP-FPM Pool (B)                 │
        (pm = ondemand)          (pm = ondemand)                  │
        open_basedir Jail        open_basedir Jail                │
        Syscalls Disabled        Syscalls Disabled                │
        Dynamic RAM Sizing       Dynamic RAM Sizing               │
                │                        │                        │
                └───────────┬────────────┘                        │
                            ▼                                     │
           MariaDB Server (Unix Socket + Isolated DB Users)       │
                            ▲                                     │
           Redis Object Cache (systemd supervised) ───────────────┘
```

---

## 📂 Repository Structure

```text
bashboard/
├── bashboard.sh                    # Core TUI Monitor, Status Loop & Dynamic Dispatcher (v1.8.0)
├── README.md                       # Systems Architecture & Operator Manual
└── scripts/                        # Modular Workload Engines
    ├── 01_install_lemp.sh          # [1] Dual-OS LEMP Provisioner (Sury Keyring / Ondrej PPA)
    ├── 02_create_vhost.sh          # [2] VHost Deployer (Webroot ACME TLS, Syscall Lock, Sandboxes)
    ├── 03_wordpress_manager.sh     # [3] WP Manager (Multi-PHP CLI Pinning, 5m Cron, WSOD Fix)
    ├── 04_harden_security.sh       # [4] Security Hardening (Anti-Lockout SSH, UFW, Fail2Ban)
    ├── 06_log_optimizer.sh         # [6] Logrotate Optimizer (Orphan Sanitizer & Journal Vacuum)
    ├── 07_delete_vhost.sh          # [7] Atomic 8-Tier Tenant Purge Engine (Manifest Driven)
    └── 12_backup_gdrive.sh         # [12] Offsite Backup Engine (Headless Cron & Non-locking Dumps)
```

---

## 🚀 Modular Engine Details

### `[1]` LEMP Stack Provisioner (`01_install_lemp.sh`)
* **Dual-OS Repository Management:** Detects Debian vs. Ubuntu via `/etc/os-release`. Imports official Sury GPG keyrings on Debian (`packages.sury.org`) and Ondrej PPAs on Ubuntu.
* **Global Nginx Primitives:** Automatically unlinks the stock `/etc/nginx/sites-enabled/default` symlink to prevent vhost collisions, deploys Cloudflare Real-IP restoration (`/etc/nginx/conf.d/00-cloudflare-realip.conf`), and configures a global login rate-limiting zone (`wplogin` at `10r/m`).
* **Dual-Mode MariaDB Authentication:** Preserves native `unix_socket` authentication on modern MariaDB (`10.4+`) alongside optional password authentication (`IDENTIFIED VIA unix_socket OR mysql_native_password`), ensuring headless root automation scripts never break when a password is set.
* **Task Logging:** Diverts verbose package outputs to `/var/log/bashboard_lemp_install.log` while rendering real-time `[OK]` status lines.

### `[2]` Virtual Host & Tenant Provisioner (`02_create_vhost.sh`)
* **Collision-Resistant Tenant Identities:** Generates unprivileged system users with an MD5-derived 4-character suffix (`v_${name}_${hash}`) and `/usr/sbin/nologin`.
* **Commercial Permissions Model:** Parent directory `/var/www/$DOMAIN` is locked to `750` (`$vhost_user:www-data`), blocking neighboring tenants (`Other = ---`). Web payloads are owned by `$vhost_user:$vhost_user` with `FS_METHOD = 'direct'` and `wp-config.php` restricted to `0600`.
* **True PHP Sandboxing (`open_basedir` + `disable_functions`):** Isolates temporary files and sessions into `/var/www/$DOMAIN/tmp/` (`chmod 700`), removes global `/tmp/` from `open_basedir`, and blocks shell-execution syscalls (`exec`, `shell_exec`, `system`, `passthru`, `proc_open`, `popen`, `pcntl_exec`) via `php_admin_value` so `open_basedir` cannot be bypassed via OS binaries.
* **Realpath Cache & Dynamic RAM Rebalancer:** Tunes `realpath_cache_size = 4096k` to offset `open_basedir` stat overhead. Dynamically calculates `pm.max_children` across all active pools after reserving 20% of host RAM (min 1536MB) for the OS and database.
* **Zero-Mutation Webroot Let's Encrypt Engine:** Verifies public DNS resolution via a multi-tier resolver (`dig` -> IP-based DoH -> `host`) against kernel network interface IPs before requesting certificates. Uses `certbot certonly --webroot` to obtain certificates without allowing Certbot's `--nginx` plugin to mutate or corrupt virtual host files. Gracefully excludes unconfigured optional subdomains (`uploads` or `www`) rather than aborting primary domain TLS issuance.
* **Post-TLS Loopback Pinning:** Pins `127.0.0.1` entries in `/etc/hosts` strictly *after* ACME validation completes, ensuring zero-latency internal WordPress loopback requests without interfering with pre-flight DNS checks.

### `[3]` WordPress Site Manager (`03_wordpress_manager.sh`)
* **Multi-PHP CLI Binary Pinning:** Reads the site's assigned `PHP_VER` from `.bashboard-state` and executes both interactive WP-CLI commands and background cron jobs using the exact matching binary (`/usr/bin/phpX.Y`), preventing version mismatch crashes on multi-PHP servers.
* **Privilege-Dropped WP-CLI (`wp_run`):** Executes all WP-CLI operations under the tenant's Linux account (`runuser -u "$u"`) with isolated cache paths (`/var/www/$DOMAIN/tmp/wp-cache`), preventing compromised plugins from executing code as `root`.
* **Tenant-Isolated System Crontab (5-Minute Cadence):** Automatically sets `DISABLE_WP_CRON = true` in `wp-config.php` and installs a staggered `/etc/cron.d/bashboard-wp-*` job wrapped in `flock` (`/usr/local/bin/bashboard-cron-runner`) that executes due cron events and WooCommerce Action Scheduler batches every 5 minutes.
* **WSOD Recovery & Zero-Leak Debugging:** Deactivates broken plugins via `--skip-plugins` and toggles `WP_DEBUG_LOG = true` while enforcing `WP_DEBUG_DISPLAY = false`.

### `[4]` DevSecOps Hardening Engine (`04_harden_security.sh`)
* **Anti-Lockout Sudoer Sentinel:** Prohibits setting `PermitRootLogin no` unless at least one active non-root user in group `sudo` or `wheel` with a valid login shell is verified.
* **OpenSSH Drop-in & Socket Compatibility:** Deploys `/etc/ssh/sshd_config.d/00-bashboard-hardening.conf` (first-match-wins precedence), ensures `/run/sshd` exists prior to `sshd -t` validation, and supports Ubuntu 24.04+ `ssh.socket` reloads.
* **Journald-Aware Fail2Ban:** Automatically installs `python3-systemd` and configures `backend = systemd` on modern Debian 12 and Ubuntu 24.04+ nodes where `/var/log/auth.log` is absent.
* **Cloud-Safe Kernel Hardening:** Configures `/etc/sysctl.d/99-bashboard-security.conf` with loose reverse-path filtering (`rp_filter = 2`), SYN flood protection, and VFS symlink/hardlink protections.

### `[6]` Log Rotation Optimizer (`06_log_optimizer.sh`)
* **Orphaned Drop-in Sanitizer & Sync:** Removes stale `/etc/logrotate.d/vhost-*` files left behind by manually deleted directories, then synchronizes active tenant logrotate policies using state-manifest user lookups.
* **Zero-Loss Rotation & Journald Caps:** Rotates Nginx logs via `USR1` signals and PHP slowlogs via `copytruncate`. Caps `systemd-journald` disk usage (`SystemMaxUse=150M` by default) and performs immediate vacuuming.

### `[7]` Virtual Host Purge Engine (`07_delete_vhost.sh`)
* **Manifest-Driven 8-Tier Eradication:** Reads `.bashboard-state` to identify exact database and tenant user bindings. Terminates active tenant processes (`SIGTERM` -> `SIGKILL`), removes PHP-FPM pools, rebalances remaining worker limits, purges ACME certificates, sanitizes `/etc/hosts` and `/etc/cron.d/`, and validates stack health (`nginx -t` & `php-fpm -t`).

### `[12]` Automated Google Drive Backup Engine (`12_backup_gdrive.sh`)
* **Dual-Tier Non-Locking Database Dumps:** Runs `mariadb-dump --single-transaction --quick --routines --triggers` via root socket authentication, falling back automatically to tenant-level `wp db export` if custom root credentials block passwordless CLI access. Verifies gzip payload size (`> 64 bytes`) to prevent uploading empty header-only archives.
* **Headless Cron & Interactive TUI Modes:** Supports interactive configuration as well as unattended `--non-interactive` execution at 03:00 AM via `/etc/cron.d/bashboard-gdrive-backup`.

---

## 🗺️ System Footprint & Generated Files Matrix

Beyond individual virtual host directories (`/var/www/$DOMAIN`), Bashboard creates and manages the following system-level files:

| File / Directory Path | Created By | Purpose & Lifecycle |
| :--- | :--- | :--- |
| `/run/bashboard.lock` | `bashboard.sh` | Exclusive `flock` (FD 200) preventing concurrent dashboard sessions. |
| `/run/bashboard_ip` | `bashboard.sh` | Cached public IPv4 address (detected via kernel NICs first, outbound HTTP fallback). |
| `/var/log/bashboard.log` | `bashboard.sh` | Central audit trail of module executions and exit codes. |
| `/var/log/bashboard_lemp_install.log` | `01_install_lemp.sh` | Full APT and service provisioning output log. |
| `/var/log/bashboard_ssl.log` | `02_create_vhost.sh` | Certbot ACME issuance and verification log. |
| `/var/log/bashboard_backup.log` | `12_backup_gdrive.sh` | Nightly unattended Google Drive backup execution log. |
| `/usr/local/bin/wp` | `01` / `03` | Official WP-CLI PHAR binary. |
| `/usr/local/bin/bashboard-cron-runner` | `03_wordpress_manager.sh` | Atomic `flock` wrapper executing Multi-PHP WP-Cron and Action Scheduler tasks. |
| `/etc/nginx/conf.d/00-cloudflare-realip.conf` | `01_install_lemp.sh` | Cloudflare IPv4/IPv6 ranges for restoring visitor IPs (`CF-Connecting-IP`). |
| `/etc/nginx/conf.d/00-bashboard-rate-limit.conf` | `01` / `02` | Global Nginx `limit_req_zone` (`wplogin`, 10 req/min, HTTP 429). |
| `/etc/nginx/snippets/ssl-params.conf` | `01` / `02` | Hardened TLSv1.2 / TLSv1.3 cipher and session settings. |
| `/etc/letsencrypt/renewal-hooks/deploy/bashboard-nginx-reload.sh` | `02_create_vhost.sh` | Post-renewal hook that safely reloads Nginx after automated Certbot renewals. |
| `/etc/sysctl.d/99-bashboard-security.conf` | `04_harden_security.sh` | Kernel network and VFS security parameters. |
| `/etc/ssh/sshd_config.d/00-bashboard-hardening.conf` | `04_harden_security.sh` | High-priority OpenSSH daemon hardening directives. |
| `/etc/fail2ban/jail.d/00-bashboard.conf` | `04_harden_security.sh` | SSH intrusion prevention rules (`ufw` banaction, `systemd` backend). |
| `/etc/systemd/journald.conf.d/99-bashboard-limits.conf` | `06_log_optimizer.sh` | Systemd journal storage ceiling configuration. |
| `/etc/cron.d/bashboard-wp-<domain>` | `03_wordpress_manager.sh` | Per-site 5-minute cron schedule running as the unprivileged tenant user. |
| `/etc/cron.d/bashboard-gdrive-backup` | `12_backup_gdrive.sh` | Nightly 03:00 AM automated offsite backup job. |
| `/var/backups/bashboard/` | `03` / `12` | Root-restricted (`0700`) vault for manual DB exports and `gdrive-staging/`. |
| `/root/.config/rclone/rclone.conf` | Operator / `12` | Root `rclone` configuration file containing Google Drive OAuth tokens. |

---

## 🛠️ Installation & Quickstart

### System Requirements
* **Operating System:** Ubuntu 22.04 / 24.04 / 26.04 LTS or Debian 11 / 12
* **Privileges:** Root access (`sudo -i`)
* **Terminal Geometry:** 95+ Columns recommended

```bash
# 1. Switch to root and clone the repository into /opt/
sudo -i
cd /opt
git clone https://github.com/HamxaBoustani/bashboard.git
cd bashboard

# 2. Grant administrative execution permissions across the suite
chmod 700 bashboard.sh scripts/*.sh
chown -R root:root /opt/bashboard

# 3. Launch Bashboard Control Engine
./bashboard.sh
```

---

## ⚙️ Operator Configuration Guides

### 1. Google Drive Off-Site Backup Setup (`rclone`)

Bashboard uses `rclone` to stream backups to Google Drive. Because a Linux VPS has no local web browser, authorization is performed headlessly.

> ⚠️ **CRITICAL PRIVILEGE NOTE:** Bashboard and its nightly cron job execute strictly as **`root`**. Always run `sudo rclone config` (or run it inside a `sudo -i` root shell) so the configuration is saved to `/root/.config/rclone/rclone.conf`. If you configure `rclone` as a standard user (e.g., `ubuntu`), you must copy the config file to `/root/.config/rclone/rclone.conf`.

#### Step 1: Install rclone (if not already installed)
Launching Option `[12]` in Bashboard installs `rclone` automatically, or you can install it manually:
```bash
curl https://rclone.org/install.sh | sudo bash
```

#### Step 2: Initialize the Remote as Root
Run the configuration wizard with `sudo`:
```bash
sudo rclone config
```
Follow the prompts carefully:
1. **`n`** -> Create a `New remote`.
2. **`name>`** -> Type strictly: **`bashboard-gdrive`**
3. **`Storage>`** -> Type **`drive`** (Google Drive).
4. **`client_id>`** -> **Press `Enter` (Leave completely blank)** unless you have created your own custom Google Cloud OAuth Client ID. *(⚠️ Do NOT type `n` here, or Google will reject authentication with an `invalid_client` error!)*
5. **`client_secret>`** -> **Press `Enter` (Leave completely blank)** unless using your own custom credentials. *(⚠️ Do NOT type `n` here!)*
6. **`scope>`** -> Type **`1`** (Full access to all files, excluding Application Data Folder).
7. **`root_folder_id>`** -> **Press `Enter`** (Leave blank).
8. **`service_account_file>`** -> **Press `Enter`** (Leave blank).
9. **`Edit advanced config?`** -> Type **`n`**.
10. **`Use web browser to automatically authenticate rclone with remote?`** -> Type **`n`** (since the VPS is headless).

#### Step 3: Authorize Your Google Account
The server terminal will now pause at `config_token>` and ask you to run `rclone authorize "drive"` on a machine with a web browser. Choose one of the two methods below:

* **Method A: Authorize on your local laptop (Windows / macOS / Linux)**
  1. Install `rclone` on your local computer and run:
     ```bash
     rclone authorize "drive"
     ```
  2. Your local browser will open. Log in to your Google account and click **Allow**.
  3. Copy the entire JSON token block (`{"access_token":"..."}`) printed in your local terminal, paste it into the **server's** `config_token>` prompt, and press `Enter`.

* **Method B: SSH Port Forwarding (No local `rclone` installation required)**
  1. Open a second terminal on your laptop and connect to the VPS with port `53682` forwarded:
     ```bash
     ssh -L 53682:127.0.0.1:53682 root@YOUR_SERVER_IP
     ```
  2. If using this tunnel during Step 2 (Question 10), you can answer **`y`** instead of `n` and open the generated `http://127.0.0.1:53682/auth?...` link directly in your laptop's browser.

#### Step 4: Finalize & Save
1. **`Configure this as a Shared Drive (Team Drive)?`** -> Type **`n`**.
2. **`Keep this "bashboard-gdrive" remote?`** -> Type **`y`**.
3. Type **`q`** to quit the wizard.

*(Note: If you accidentally ran `rclone config` as a non-root user, copy it to root immediately:)*
```bash
sudo mkdir -p /root/.config/rclone
sudo cp ~/.config/rclone/rclone.conf /root/.config/rclone/rclone.conf
sudo chmod 600 /root/.config/rclone/rclone.conf
```

#### Step 5: Verify Root Connection & Enable Nightly Cron
```bash
# Verify that root can list your Google Drive directories without errors:
sudo rclone lsd bashboard-gdrive:
```
Once verified, launch `./bashboard.sh`, select **`[12]`**, press **`[9]`** to run an immediate test backup, and press **`[8]`** to install the 03:00 AM nightly cron job.

> 💡 **Production Best Practice (Custom Google Client ID):** By default, `rclone` uses a shared public Client ID which is subject to global rate limits and scheduled for retirement by `rclone`. For production servers, create a free project in the [Google Cloud Console](https://console.cloud.google.com/), enable the **Google Drive API**, create a **Desktop App** OAuth Client ID, and provide your own `client_id` and `client_secret` during Step 2.

---

### 2. Configuring the Static Media Subdomain (`uploads.domain.com`)

When deploying a Virtual Host in Module **`[2]`**, toggling Option **`[4] Uploads Subdomain`** to `ENABLED` provisions:
1. A dedicated directory at `/var/www/example.com/public_html/uploads`.
2. An isolated Nginx `server` block for `uploads.example.com` with 365-day cache headers, CORS (`Access-Control-Allow-Origin "*"`), and strict PHP execution denial (`deny all`).
3. Let's Encrypt TLS coverage for `uploads.example.com` (provided its DNS `A` or `CNAME` record points to the server).

Because Bashboard does not hardcode media URLs into your database automatically, **you must complete two manual steps** if you enable this feature:

1. **DNS Record:** Create an `A` or `CNAME` record for `uploads.example.com` pointing to your server IP before running Module `[2]`.
2. **WordPress Configuration:** Add the custom upload path constant to `/var/www/example.com/public_html/wp-config.php` (above the `/* That's all, stop editing! */` line):
   ```php
   define( 'UPLOADS', 'uploads' );
   ```
   *(Optionally, set `upload_url_path` to `https://uploads.example.com` in WordPress Settings / WP-CLI so media URLs rewrite to the cookieless subdomain:* `wp option update upload_url_path "https://uploads.example.com"`*)*.

---

### 3. Cloudflare & DNS Pre-Flight Considerations

Module **`[2]`** performs a strict Pre-Flight DNS check against public resolvers (`1.1.1.1`, `8.8.8.8`, `9.9.9.9`) before invoking Let's Encrypt:
* When provisioning a **new site**, set your domain's `A` record (`@`) and `www` record in Cloudflare to **DNS Only (Grey Cloud)** so the public DNS resolves directly to your VPS IPv4 address.
* Once Module `[2]` issues and binds the official Let's Encrypt certificate, you can safely switch Cloudflare back to **Proxied (Orange Cloud)** with SSL/TLS mode set to **Full (Strict)**. Nginx is pre-configured with `00-cloudflare-realip.conf` to restore real visitor IP addresses automatically.

---

## 📋 Recommended Operator Provisioning Workflow

When configuring a brand-new production node, follow this sequence:

```text
[Step 1] Option [1]  -> Provision LEMP Stack (Nginx, MariaDB, PHP-FPM, Redis, WP-CLI)
[Step 2] Option [4]  -> Enforce Security Hardening (UFW Firewall, Fail2Ban, Sysctl, SSH)
[Step 3] Option [2]  -> Deploy Virtual Host (Select WordPress or Blank, Isolated Tenant, TLS)
[Step 4] Option [3]  -> WordPress Manager (Toggle System 5m WP-Cron, Verify Checksums)
[Step 5] Option [6]  -> Log Optimizer (Synchronize dedicated drop-ins & Cap Journald)
[Step 6] Option [12] -> Configure Google Drive Backup (Verify rclone & Enable 03:00 AM Cron)
```

---

## 🔍 Verification & Diagnostics Cheat Sheet

Verify your server's runtime health and security isolation using these commands:

### 1. Verify Multi-Tenant POSIX Isolation (Lateral Movement Test)
Simulate a compromised tenant shell on Site B attempting to read Site A's configuration:
```bash
# Attempt to read Site A's database credentials as Site B's isolated user:
sudo -u v_site_b_xxxx cat /var/www/site-a.com/public_html/wp-config.php

# Expected Output:
# cat: /var/www/site-a.com/public_html/wp-config.php: Permission denied
```

### 2. Verify `open_basedir` & Syscall Lockdown
Verify that PHP blocks reading system files and blocks shell execution functions:
```bash
# 1. Test open_basedir restriction:
sudo -u v_example_com_xxxx php -d open_basedir="/var/www/example.com/:/dev/urandom" \
  -r "echo is_readable('/etc/passwd') ? 'LEAK' : 'BLOCKED';"
# Expected Output: BLOCKED

# 2. Inspect disabled functions in the tenant's pool configuration:
grep "disable_functions" /etc/php/*/fpm/pool.d/example_com.conf
```

### 3. Verify Cross-Tenant Temporary & Session Sandboxing
```bash
# Verify that the tenant's temp sandbox is locked down to mode 700:
ls -ld /var/www/example.com/tmp
# Must show: drwx------ v_example_com_xxxx v_example_com_xxxx
```

### 4. Verify One-Click WordPress Dashboard Permissions
```bash
# Parent directory must be 750 (tenant:www-data), wp-config.php must be 600:
ls -ld /var/www/example.com
# Must show: drwxr-x--- v_example_com_xxxx www-data

ls -l /var/www/example.com/public_html/wp-config.php
# Must show: -rw------- 1 v_example_com_xxxx v_example_com_xxxx
```

### 5. Verify Zero-Trust Upload Sandboxing
```bash
# Create a dummy PHP file inside the uploads directory
echo "<?php phpinfo(); ?>" > /var/www/example.com/public_html/wp-content/uploads/test.php

# Request via curl (Must return 403 Forbidden or 404 Not Found, NEVER 200 OK)
curl -k -I https://example.com/wp-content/uploads/test.php

# Clean up test file
rm -f /var/www/example.com/public_html/wp-content/uploads/test.php
```

### 6. Verify Tenant-Isolated WP-Cron Offloading
```bash
# Inspect the active system cron drop-in:
cat /etc/cron.d/bashboard-wp-*

# Test manual cron execution strictly under the tenant's sandboxed environment:
sudo -u v_example_com_xxxx \
  HOME=/var/www/example.com \
  WP_CLI_CACHE_DIR=/var/www/example.com/tmp/wp-cache \
  php /usr/local/bin/wp cron event list --path=/var/www/example.com/public_html
```

---

## 🚨 Troubleshooting & Disaster Recovery

### 1. `rclone` Error: `couldn't fetch token: invalid_client`
* **Cause:** During `rclone config`, a character (such as `n`) was typed into the `client_id` or `client_secret` prompt instead of leaving it blank, or the token was generated with an incompatible `rclone` version.
* **Fix:** Strip the invalid lines from `/root/.config/rclone/rclone.conf`:
  ```bash
  sudo sed -i '/^client_id/d; /^client_secret/d' /root/.config/rclone/rclone.conf
  sudo rclone lsd bashboard-gdrive:
  ```

### 2. Let's Encrypt Pre-Flight Skipped (Domain Points to Cloudflare IP or Unresolved)
* **Cause:** Either the domain's DNS has not propagated to public resolvers (`1.1.1.1` / `8.8.8.8`), or Cloudflare Proxy (Orange Cloud) is hiding the server's real IP during initial setup.
* **Fix:** Set the DNS record to **DNS Only (Grey Cloud)** in Cloudflare, wait 1–2 minutes, and issue the certificate cleanly via Webroot without recreating the site:
  ```bash
  sudo certbot certonly --webroot -w /var/www/example.com/public_html \
    --cert-name example.com --non-interactive --agree-tos \
    --email admin@example.com --no-eff-email \
    -d example.com -d www.example.com && \
  sudo sed -i "s|/etc/nginx/ssl/example.com.crt|/etc/letsencrypt/live/example.com/fullchain.pem|g" /etc/nginx/sites-available/example.com && \
  sudo sed -i "s|/etc/nginx/ssl/example.com.key|/etc/letsencrypt/live/example.com/privkey.pem|g" /etc/nginx/sites-available/example.com && \
  sudo rm -f /etc/nginx/ssl/example.com.crt /etc/nginx/ssl/example.com.key && \
  sudo nginx -t && sudo systemctl reload nginx
  ```

### 3. `502 Bad Gateway` Outage
If Nginx responds with `502 Bad Gateway`, inspect the dedicated error log and socket:
```bash
# 1. Tail the virtual host's dedicated error log
tail -n 20 /var/www/example.com/logs/nginx_error.log

# 2. Verify that the dedicated PHP-FPM socket exists
ls -la /run/php/php*-fpm-example_com.sock
# Must show: srw-rw---- 1 www-data www-data

# 3. Validate PHP-FPM pool syntax across all installed versions
for fpm in /usr/sbin/php-fpm*; do "$fpm" -t; done
```

### 4. WordPress White Screen of Death (WSOD)
If a faulty plugin update crashes a WordPress site:
1. Launch `./bashboard.sh` -> Select **`[3] WordPress Manager`** -> Choose the target domain.
2. Select **`[6] 🚨 Deactivate ALL Plugins (WSOD Fix)`**.
3. Bashboard executes `wp plugin deactivate --all --skip-plugins` as the tenant user, bypassing broken plugin code and restoring site availability immediately.

---

## 🤝 Contributing & Extending Modules

1. Fork the repository.
2. Add custom workload scripts into `scripts/` following the naming convention: `scripts/XX_module_name.sh`.
3. Enforce strict mode compliance at the top of every script: `set -euo pipefail`.
4. Ensure scripts are idempotent, validate syntax before reloading daemons, and close or ignore file descriptor `200` if spawning background daemons.
5. Submit a Pull Request.

---

## 📜 License
This project is licensed under the **MIT License**. Engineered for production use on bare-metal and cloud Linux VPS nodes.