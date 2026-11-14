# 🚀 Bashboard: Lightweight Linux VPS & LEMP Control Plane

![Version](https://img.shields.io/badge/Version-1.8.0-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Ubuntu_22.04%20|%2024.04%20|%2026.04_LTS%20|%20Debian_11%20|%2012-lightgrey.svg?logo=linux)
![Architecture](https://img.shields.io/badge/Architecture-Modular_Bash_TUI_%7C_Zero--Daemon-green.svg)
![Security](https://img.shields.io/badge/Security-POSIX_Isolated_%7C_CLI_&_FPM_Sandboxed-red.svg)
![License](https://img.shields.io/badge/License-MIT-orange.svg)

**Bashboard** is a zero-overhead, modular terminal control plane and automation suite written in Bash. Engineered for standalone Linux VPS instances hosting multiple internal projects, agency client sites, or private eCommerce stores, Bashboard provides automated LEMP stack deployment, per-site on-demand PHP-FPM resource isolation, non-locking offsite backups to Google Drive, and automated Nginx virtual host management without running persistent background control panel daemons.

---

## 📌 Scope, Threat Model & Architectural Philosophy

### What Bashboard Is
* **A Zero-Daemon CLI/TUI Control Plane:** Bashboard executes purely within an active administrative SSH session. When closed, **zero management processes or control panel daemons remain in RAM**. All available hardware resources are dedicated to Nginx, MariaDB, Redis, and PHP-FPM.
* **A Blast-Radius Compartmentalizer:** Tailored for developer teams, agencies, and self-hosted server environments. If one WordPress site is compromised via a vulnerable plugin, Root-Anchored POSIX permission boundaries (`0750`), PHP filesystem sandboxing (`open_basedir`), and function lockdown (`disable_functions` across both PHP-FPM and PHP-CLI) prevent lateral movement to neighboring virtual hosts or system files.
* **A Safe Operational Wrapper:** Replaces error-prone manual configuration with idempotent, rollback-aware Bash scripts that validate syntax (`nginx -t`, `php-fpm -t`, `sshd -t`, `logrotate -d`) prior to triggering service reloads.

### What Bashboard Is Not & Security Trade-Offs
* **Not Public Shared Hosting Infrastructure:** Bashboard is not a drop-in replacement for CloudLinux, CageFS, or cPanel when hosting untrusted, hostile third-party customers. It relies on Linux POSIX permissions and PHP pool/CLI configuration rather than kernel-level `cgroups v2` resource virtualization or namespace `chroot` jails.
* **`FS_METHOD = 'direct'` Usability Trade-Off:** To allow administrators to install and update plugins/themes with one click directly from the WordPress dashboard without FTP prompts, `/var/www/$DOMAIN/public_html` is writable by the site's dedicated tenant user (`v_<site>_<hash>`). While neighboring sites are completely blocked from accessing this directory, a remote code execution (RCE) vulnerability within a site's plugin can modify PHP files inside that specific site's `public_html`.

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
           (HTTP/2 | TLS 1.3 | Cloudflare Real-IP | 444 Default Catch-All)
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        ▼                                ▼                                ▼
[ VHost: site-a.com ]            [ VHost: site-b.com ]          [ Loopback: 127.0.0.1:8080 ]
 (User: v_site_a_xxxx)            (User: v_site_b_yyyy)          (phpMyAdmin via SSH Tunnel)
 Parent Dir: 750 (root:v_site_a)  Parent Dir: 750 (root:v_site_b) (User: v_pma_sys)
 Logs Dir: 750 (www-data:v_site_a)Logs Dir: 750 (www-data:v_site_b)(No /var/www/* Access)
 Web Root: 755/644 (v_site_a)     Web Root: 755/644 (v_site_b)            │
 wp-config: 600                   wp-config: 600                          │
 Temp: /site-a/tmp/ (700)         Temp: /site-b/tmp/ (700)                │
        │                                │                                │
FastCGI Unix Socket              FastCGI Unix Socket              FastCGI Unix Socket
/run/php/...-site_a_xxxx.sock    /run/php/...-site_b_yyyy.sock    /run/php/...-phpmyadmin.sock
        │                                │                                │
        ▼                                ▼                                ▼
PHP-FPM Pool & CLI (A)           PHP-FPM Pool & CLI (B)           PHP-FPM Pool (PMA)
(pm = ondemand)                  (pm = ondemand)                  (pm = ondemand)
open_basedir & Function Lock     open_basedir & Function Lock     open_basedir (/usr/share/...)
        │                                │                                │
        └────────────────────────────────┼────────────────────────────────┘
                                         ▼
                MariaDB Server (Unix Socket + Hashed Isolated DB Users)
                                         ▲
                Redis Object Cache (systemd supervised | Admin Commands Disabled)
```

---

## 📂 Repository Structure

```text
bashboard/
├── bashboard.sh                    # Core TUI Monitor, Status Loop & Dynamic Dispatcher (v1.8.0)
├── README.md                       # Systems Architecture & Operator Manual
└── scripts/                        # Modular Workload Engines
    ├── 01_install_lemp.sh          # [1] Dual-OS LEMP & Sandboxed phpMyAdmin Provisioner
    ├── 02_create_vhost.sh          # [2] VHost Deployer (Root-Anchored Dir, Webroot ACME, FPM Lock)
    ├── 03_wordpress_manager.sh     # [3] WP Manager (Sandboxed Multi-PHP CLI/Cron, WSOD Fix)
    ├── 04_harden_security.sh       # [4] Security Hardening (Dual Anti-Lockout SSH, UFW, Fail2Ban)
    ├── 06_log_optimizer.sh         # [6] Logrotate Optimizer (CVE-2016-1247 Safe & Journal Vacuum)
    ├── 07_delete_vhost.sh          # [7] Atomic 8-Tier Tenant Purge Engine (Manifest Driven)
    └── 12_backup_gdrive.sh         # [12] Offsite Backup Engine (Flock Guard & Non-locking Dumps)
```

---

## 🚀 Modular Engine Details

### `[1]` LEMP Stack & phpMyAdmin Provisioner (`01_install_lemp.sh`)
* **Dual-OS Repository Management & Dynamic APT Resolver:** Detects Debian vs. Ubuntu via `/etc/os-release`. Imports official Sury GPG keyrings on Debian (`packages.sury.org`) and Ondrej PPAs on Ubuntu. Dynamically verifies package availability in APT cache (`apt-cache policy`) prior to installation, seamlessly handling PHP `8.5+` built-in `opcache` and generic PECL fallbacks (`php-redis`, `php-imagick`) with a 60-second `dpkg` lock timeout (`DPkg::Lock::Timeout=60`).
* **Global Nginx Primitives:** Unlinks the stock `/etc/nginx/sites-enabled/default` symlink, deploys Cloudflare Real-IP restoration (`00-cloudflare-realip.conf`), and configures a global login rate-limiting zone (`wplogin` at `10r/m`).
* **Dual-Mode MariaDB Authentication:** Preserves native `unix_socket` authentication on MariaDB (`10.4+`) alongside optional password authentication (`IDENTIFIED VIA unix_socket OR mysql_native_password`), ensuring headless root automation scripts never break when a password is set.
* **Hardened Redis Cache:** Enforces `supervised systemd` and disables destructive administrative/blocking commands (`KEYS`, `MONITOR`, `CONFIG`, `SHUTDOWN`, `DEBUG`, `BGSAVE`, `SAVE`, `SLAVEOF`, `REPLICAOF`) while keeping non-blocking `SCAN` open for WordPress cache group flushing.
* **Zero-Public-Exposure phpMyAdmin (`127.0.0.1:8080`):** Installs phpMyAdmin non-interactively without Apache bloat, binds it strictly to `127.0.0.1:8080` (`/etc/nginx/conf.d/00-bashboard-phpmyadmin.conf`) for SSH-Tunnel access only, and isolates its execution inside a dedicated `v_pma_sys` PHP-FPM pool that has zero `open_basedir` access to `/var/www/*`.

### `[2]` Virtual Host & Tenant Provisioner (`02_create_vhost.sh`)
* **Collision-Resistant Hashed Identifiers:** Appends a 4-character MD5 domain hash suffix to the Linux tenant user (`v_${slug}_${hash}`), PHP-FPM pool (`${slug}_${hash}`), database name (`${slug}_${hash}`), and database user (`u_${slug}_${hash}`), eliminating truncation collisions across multi-subdomain deployments.
* **Root-Anchored Chroot-Style Directory Hierarchy (`C1` & `C2` Hardened):**
  * Base directory `/var/www/$DOMAIN` is owned by **`root:$vhost_user` (`0750`)** with `www-data` added to group `$vhost_user`. Because `root` owns the parent directory, a compromised tenant cannot `unlink` or tamper with `.bashboard-state` or rename the `logs/` directory.
  * Authoritative state manifests are stored in root-restricted **`/etc/bashboard/sites/${DOMAIN}.state` (`0600`)**.
  * Logs directory `/var/www/$DOMAIN/logs` is owned by **`www-data:$vhost_user` (`0750`)**, giving the tenant read-only access to logs while preventing `CVE-2016-1247` symlink privilege escalation during Nginx reloads or logrotate cycles.
* **PHP-FPM Sandboxing (`open_basedir` + `disable_functions`):** Isolates temporary files and sessions into `/var/www/$DOMAIN/tmp/` (`0700`), removes global `/tmp/` from `open_basedir`, hides `expose_php`, blocks `xmlrpc.php` at the Nginx layer, and disables shell-spawning functions (`exec`, `passthru`, `shell_exec`, `system`, `proc_open`, `popen`, `pcntl_exec`, `show_source`, `highlight_file`, `proc_get_status`, `posix_*`).
* **Catch-All Default Server & Webroot ACME TLS:** Deploys a `default_server` catch-all block (`00-bashboard-default-catchall.conf`) returning HTTP `444` to prevent unknown Host headers from hitting tenant sites. Verifies public DNS (`dig` -> IP DoH -> `host`) against kernel interface IPs and issues Let's Encrypt certificates via `certbot certonly --webroot` without mutating Nginx configuration structure. Gracefully excludes unconfigured optional subdomains (`uploads` or `www`) rather than aborting primary domain TLS issuance.

### `[3]` WordPress Site Manager (`03_wordpress_manager.sh`)
* **Sandboxed Multi-PHP CLI & Cron Execution (`C3` Hardened):** Reads `PHP_VER` from `/etc/bashboard/sites/${DOMAIN}.state` and executes both interactive WP-CLI commands (`wp_run`) and background cron jobs (`/usr/local/bin/bashboard-cron-runner`) under the tenant user (`runuser -u`) with explicit `-d open_basedir=...` and `-d disable_functions=...` flags, ensuring CLI/Cron cannot be used by rogue plugins to bypass FPM restrictions.
* **Symlink-Safe Permission Enforcer & Stdin Password Piping:** Executes recursive `chmod` operations under the unprivileged tenant user context to prevent root symlink race conditions, and pipes administrator passwords via `stdin` (`--prompt=user_pass`) so credentials never appear in `/proc` or `ps` process tables.
* **Persistent Maintenance Mode:** Writes a 1-year future integer timestamp into `.maintenance` to prevent WordPress's 10-minute auto-expiration timeout and clears stale `core_updater.lock` database options upon deactivation.
* **Direct Non-Locking Database Exports:** Uses `mariadb-dump --single-transaction --quick` directly in Option `[8]` so database backups succeed without requiring `proc_open` inside PHP-CLI.

### `[4]` DevSecOps Hardening Engine (`04_harden_security.sh`)
* **Dual Anti-Lockout Sentinel:**
  * *Gate 1:* Prohibits setting `PermitRootLogin no` unless at least one active non-root user in group `sudo` or `wheel` with a valid login shell is verified.
  * *Gate 2:* Prohibits disabling root password login (`prohibit-password`) on fresh servers if neither a non-root sudoer user nor a root SSH public key (`/root/.ssh/authorized_keys`) exists, preventing accidental terminal lockouts.
* **Clean UFW & Journald-Aware Fail2Ban:** Opens active SSH, HTTP (80), and HTTPS (443) ports, purges duplicate named profiles (`OpenSSH`, `Nginx Full`), installs `python3-systemd`, and configures Fail2Ban with `backend = systemd` and `banaction = ufw`.
* **Cloud-Safe Kernel Hardening:** Applies `/etc/sysctl.d/99-bashboard-security.conf` (`rp_filter = 2`, `tcp_syncookies = 1`, `tcp_rfc1337 = 1`, ICMP redirect blocking, and VFS hardlink/symlink/FIFO protections).

### `[6]` Log Rotation Optimizer (`06_log_optimizer.sh`)
* **CVE-2016-1247 Safe Rotation & Orphan Sanitizer:** Purges stale `/etc/logrotate.d/vhost-*` drop-ins for deleted sites, enforces `www-data:$vhost_user` (`0750`) ownership on active log directories, rotates Nginx logs under `su www-data $vhost_user`, and caps `systemd-journald` storage (`150MB` default).

### `[7]` Virtual Host Purge Engine (`07_delete_vhost.sh`)
* **Authoritative State Lookup & Exact Globbing:** Reads `/etc/bashboard/sites/${TARGET_SITE}.state`, terminates active tenant processes (`SIGTERM` -> `SIGKILL`), removes exact Let's Encrypt directory paths (preventing prefix over-matching on neighboring TLDs), drops associated databases via `MYSQL_PWD` (preventing `/proc` leaks), and validates stack health.

### `[12]` Automated Google Drive Backup Engine (`12_backup_gdrive.sh`)
* **Exclusive Flock & Verified State Guard:** Wraps backup execution in `/run/bashboard_backup.lock` (`flock`) to prevent overlap between manual runs and the 03:00 AM cron job. Validates tenant usernames (`^v_`) and `/etc/passwd` home directories from `/etc/bashboard/sites/*.state` before invoking any fallback commands.
* **Anchored Tar Exclusions & Trash-Free Cloud Pruning:** Archives web payloads with anchored `--exclude="${domain}/logs"` and `--exclude="${domain}/tmp"` flags (preserving internal plugin directories) and prunes expired cloud archives only after verifying a successful upload using `--drive-use-trash=false`.

---

## 🗺️ System Footprint & Generated Files Matrix

Beyond individual virtual host directories (`/var/www/$DOMAIN`), Bashboard creates and manages the following system-level files:

| File / Directory Path | Created By | Purpose & Lifecycle |
| :--- | :--- | :--- |
| `/etc/bashboard/sites/*.state` | `02` / `07` | Root-owned (`0600`) authoritative state manifests for each virtual host. |
| `/run/bashboard.lock` | `bashboard.sh` | Exclusive `flock` (FD 200) preventing concurrent dashboard sessions. |
| `/run/bashboard_backup.lock` | `12_backup_gdrive.sh` | Exclusive `flock` (FD 201) preventing concurrent manual and cron backups. |
| `/run/bashboard_ip` | `bashboard.sh` | Cached public IPv4 address (detected via kernel NICs first, outbound HTTP fallback). |
| `/var/log/bashboard.log` | `bashboard.sh` | Central audit trail of module executions and exit codes. |
| `/var/log/bashboard_lemp_install.log` | `01_install_lemp.sh` | Full APT and service provisioning output log. |
| `/var/log/bashboard_ssl.log` | `02_create_vhost.sh` | Certbot ACME issuance and verification log. |
| `/var/log/bashboard_backup.log` | `12_backup_gdrive.sh` | Nightly unattended Google Drive backup execution log. |
| `/usr/local/bin/wp` | `01` / `03` | Official WP-CLI PHAR binary (`0755`). |
| `/usr/local/bin/bashboard-cron-runner` | `03_wordpress_manager.sh` | Sandboxed Multi-PHP `flock` wrapper executing WP-Cron and Action Scheduler tasks. |
| `/etc/nginx/conf.d/00-cloudflare-realip.conf` | `01_install_lemp.sh` | Cloudflare IPv4/IPv6 ranges for restoring visitor IPs (`CF-Connecting-IP`). |
| `/etc/nginx/conf.d/00-bashboard-rate-limit.conf` | `01` / `02` | Global Nginx `limit_req_zone` (`wplogin`, 10 req/min, HTTP 429). |
| `/etc/nginx/conf.d/00-bashboard-default-catchall.conf` | `02_create_vhost.sh` | Default catch-all server block dropping unknown Host headers with HTTP `444`. |
| `/etc/nginx/conf.d/00-bashboard-phpmyadmin.conf` | `01_install_lemp.sh` | Loopback-only (`127.0.0.1:8080`) Nginx listener for SSH-tunneled phpMyAdmin. |
| `/etc/php/X.Y/fpm/pool.d/phpmyadmin.conf` | `01_install_lemp.sh` | Isolated PHP-FPM pool (`v_pma_sys`) for phpMyAdmin with zero `/var/www` access. |
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

### 1. Accessing Sandboxed phpMyAdmin via SSH Tunnel (`127.0.0.1:8080`)

When installed via Module **`[1]`**, phpMyAdmin is bound strictly to `127.0.0.1:8080` and runs under an isolated system account (`v_pma_sys`). It is completely invisible to the public internet.

To access phpMyAdmin from your local workstation:
1. Open a terminal on your **local laptop** and establish an SSH port-forwarding tunnel to your server:
   ```bash
   ssh -L 8081:127.0.0.1:8080 your_ssh_user@YOUR_SERVER_IP
   ```
2. Keep that terminal window open and navigate to the following URL in your local web browser:
   ```text
   http://localhost:8081
   ```
3. Log in using any site's isolated database credentials (displayed at the end of Module `[2]` or stored in `/etc/bashboard/sites/<domain>.state`) or your MariaDB administrative user.

---

### 2. Google Drive Off-Site Backup Setup (`rclone`)

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
     ssh -L 53682:127.0.0.1:53682 your_ssh_user@YOUR_SERVER_IP
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

### 3. Configuring the Static Media Subdomain (`uploads.domain.com`)

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

### 4. Cloudflare & DNS Pre-Flight Considerations

Module **`[2]`** performs a strict Pre-Flight DNS check against public resolvers (`1.1.1.1`, `8.8.8.8`, `9.9.9.9`) before invoking Let's Encrypt:
* When provisioning a **new site**, set your domain's `A` record (`@`) and `www` record in Cloudflare to **DNS Only (Grey Cloud)** so the public DNS resolves directly to your VPS IPv4 address.
* Once Module `[2]` issues and binds the official Let's Encrypt certificate, you can safely switch Cloudflare back to **Proxied (Orange Cloud)** with SSL/TLS mode set to **Full (Strict)**. Nginx is pre-configured with `00-cloudflare-realip.conf` to restore real visitor IP addresses automatically.

---

## 📋 Recommended Operator Provisioning Workflow

When configuring a brand-new production node, follow this sequence:

```text
[Step 1] Option [1]  -> Provision LEMP Stack (Nginx, MariaDB, PHP-FPM, Redis, WP-CLI, phpMyAdmin)
[Step 2] Option [4]  -> Enforce Security Hardening (UFW Firewall, Fail2Ban, Sysctl, SSH)
[Step 3] Option [2]  -> Deploy Virtual Host (Select WordPress or Blank, Isolated Tenant, TLS)
[Step 4] Option [3]  -> WordPress Manager (Toggle System 5m WP-Cron, Verify Checksums)
[Step 5] Option [6]  -> Log Optimizer (Synchronize dedicated drop-ins & Cap Journald)
[Step 6] Option [12] -> Configure Google Drive Backup (Verify rclone & Enable 03:00 AM Cron)
```

---

## 🔍 Verification & Diagnostics Cheat Sheet

Verify your server's runtime health and security isolation using these commands:

### 1. Verify Multi-Tenant POSIX Isolation & Root-Anchored Parent (`C1` & `C2` Test)
```bash
# 1. Verify parent directory is owned by root:$vhost_user (0750) and logs by www-data:$vhost_user (0750):
ls -ld /var/www/example.com /var/www/example.com/logs
# Must show:
# drwxr-x--- 5 root     v_example_com_xxxx 4096 ... /var/www/example.com
# drwxr-x--- 2 www-data v_example_com_xxxx 4096 ... /var/www/example.com/logs

# 2. Verify tenant cannot unlink root-anchored state file:
sudo -u v_example_com_xxxx rm -f /var/www/example.com/.bashboard-state
# Expected Output: rm: cannot remove '.../.bashboard-state': Permission denied

# 3. Verify Site B cannot read Site A's wp-config.php:
sudo -u v_site_b_yyyy cat /var/www/site-a.com/public_html/wp-config.php
# Expected Output: cat: .../wp-config.php: Permission denied
```

### 2. Verify `open_basedir` & Function Lockdown (`C3` Test)
```bash
# 1. Test open_basedir restriction:
sudo -u v_example_com_xxxx php -d open_basedir="/var/www/example.com/:/dev/urandom" \
  -r "echo is_readable('/etc/passwd') ? 'LEAK' : 'BLOCKED';"
# Expected Output: BLOCKED

# 2. Inspect disabled functions in the tenant's pool configuration:
grep "disable_functions" /etc/php/*/fpm/pool.d/example_com_*.conf
```

### 3. Verify Zero-Trust Upload Sandboxing & XML-RPC Block
```bash
# 1. Create a dummy PHP file inside the uploads directory
echo "<?php phpinfo(); ?>" > /var/www/example.com/public_html/wp-content/uploads/test.php

# 2. Request via curl (Must return 403 Forbidden or 404 Not Found, NEVER 200 OK)
curl -k -I https://example.com/wp-content/uploads/test.php
rm -f /var/www/example.com/public_html/wp-content/uploads/test.php

# 3. Verify XML-RPC is blocked with 403 Forbidden:
curl -k -I https://example.com/xmlrpc.php
```

### 4. Verify Sandboxed WP-Cron Offloading
```bash
# Inspect the active system cron drop-in and runner:
cat /etc/cron.d/bashboard-wp-*
cat /usr/local/bin/bashboard-cron-runner
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
    --register-unsafely-without-email \
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
ls -la /run/php/php*-fpm-example_com_*.sock
# Must show: srw-rw---- 1 www-data www-data

# 3. Validate PHP-FPM pool syntax across all installed versions
for fpm in /usr/sbin/php-fpm*; do "$fpm" -t; done
```

### 4. WordPress White Screen of Death (WSOD)
If a faulty plugin update crashes a WordPress site:
1. Launch `./bashboard.sh` -> Select **`[3] WordPress Manager`** -> Choose the target domain.
2. Select **`[6] 🚨 Deactivate ALL Plugins (WSOD Fix)`**.
3. Bashboard executes `wp plugin deactivate --all --skip-plugins` inside the tenant sandbox, bypassing broken plugin code and restoring site availability immediately.

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
