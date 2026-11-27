# 🚀 Bashboard: Lightweight Linux VPS & LEMP Control Plane

![Version](https://img.shields.io/badge/Version-1.9.1-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Ubuntu_22.04%20|%2024.04%20|%2026.04_LTS%20|%20Debian_11%20|%2012%20|%2013-lightgrey.svg?logo=linux)
![Architecture](https://img.shields.io/badge/Architecture-Modular_Bash_TUI_%7C_Zero--Daemon-green.svg)
![Security](https://img.shields.io/badge/Security-POSIX_%2B_SHA256_Redis_ACL_%7C_Symlink_Hardened-red.svg)
![License](https://img.shields.io/badge/License-MIT-orange.svg)

**Bashboard** is a zero-overhead, modular terminal control plane and automation suite written in Bash. Engineered for standalone Linux VPS instances hosting multiple internal projects, agency client sites, or private eCommerce stores, Bashboard automates LEMP stack deployment, per-site on-demand PHP-FPM & SHA-256 Redis ACL isolation, per-site streaming offsite backups to Google Drive, and hardened Nginx virtual host management—without running persistent background web control panel daemons.

---

## 📌 Scope, Threat Model & Architectural Philosophy

### What Bashboard Is
* **A Zero-Panel-Daemon CLI/TUI Control Plane:** Bashboard executes strictly within an active administrative SSH session. When closed, **zero control panel daemons remain in RAM** (background maintenance uses standard OS `cron.d` schedules rather than persistent panel services). All memory remains dedicated to Nginx, MariaDB, Redis, and PHP-FPM.
* **A Multi-Layer Blast-Radius Compartmentalizer:** Tailored for developer teams, agencies, and self-hosted environments. If one WordPress site is compromised via a vulnerable plugin, Root-Anchored POSIX boundaries (`0750`), 3-tier symlink-hardened logging (`logs/`, `logs/php/`, and root-only `/var/log/php-fpm/`), shared root-owned ACME validation (`/var/www/_acme-challenge`), zero-root-write tenant operations, PHP/OPcache/ImageMagick sandboxing, and **per-tenant SHA-256 Redis ACL keyspace isolation** (`~<pool>:*`) prevent lateral movement or local privilege escalation.
* **A Safe Operational Wrapper:** Replaces error-prone manual configuration with idempotent, rollback-aware (`set -Eeuo pipefail`) Bash scripts that validate syntax (`nginx -t`, `php-fpm -t`, `sshd -t`, `fail2ban-client -t`, `logrotate -d`) before triggering reloads.

### What Bashboard Is Not & Security Trade-Offs
* **Not Public Shared Hosting Infrastructure:** Bashboard is not a drop-in replacement for CloudLinux, CageFS, or cPanel when hosting untrusted, hostile third-party customers. It enforces Linux POSIX permissions, Redis ACLs, and PHP pool/CLI sandboxing rather than kernel-level `cgroups v2` resource virtualization or namespace `chroot` jails.
* **`FS_METHOD = 'direct'` Usability Trade-Off:** To allow one-click plugin/theme updates directly from the WordPress dashboard without FTP prompts, `/var/www/$DOMAIN/public_html` is writable by the site's dedicated tenant user (`v_<slug>_<sha8>`). Neighboring sites remain isolated, but an RCE inside a site's plugin can modify files inside that specific site's `public_html`.
* **Loopback phpMyAdmin (`127.0.0.1:8080`):** phpMyAdmin is hidden from the public internet and rate-limited (`wplogin` zone), but because it listens on `127.0.0.1:8080`, local processes can reach its login page (MariaDB credentials are still required and its isolated `v_pma_sys` pool has zero access to `/var/www/*`).

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
         (HTTP/2 | TLS 1.3 | CIDR-Guarded CF Real-IP | 444 Catch-All)
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        ▼                                ▼                                ▼
[ VHost: site-a.com ]            [ VHost: site-b.com ]          [ Loopback: 127.0.0.1:8080 ]
 (User: v_site_a_xxxxxxxx)        (User: v_site_b_yyyyyyyy)      (phpMyAdmin via SSH Tunnel)
 Parent:   750 (root:tenant)      Parent:   750 (root:tenant)    (User: v_pma_sys | Rate-Limited)
 NginxLog: 750 (www-data:tenant)  NginxLog: 750 (www-data:tenant)(No /var/www/* Access)
 PHPErr:   750 (tenant:tenant)    PHPErr:   750 (tenant:tenant)           │
 SlowLog:  /var/log/php-fpm/ (root:root 750 - Zero Tenant Symlink Risk)   │
 ACME:     /var/www/_acme-challenge (root:root 755 - Shared Root Webroot) │
 WebRoot:  755/644 (tenant)       WebRoot:  755/644 (tenant)              │
 wp-config: 600 | tmp/: 700       wp-config: 600 | tmp/: 700              │
        │                                │                                │
FastCGI Unix Socket              FastCGI Unix Socket              FastCGI Unix Socket
/run/php/...-site_a_xxxx.sock    /run/php/...-site_b_yyyy.sock    /run/php/...-phpmyadmin.sock
        │                                │                                │
        ▼                                ▼                                ▼
PHP-FPM Pool & CLI (A)           PHP-FPM Pool & CLI (B)           PHP-FPM Pool (PMA)
(pm = ondemand | OPcache &       (pm = ondemand | OPcache &       (pm = ondemand)
 ImageMagick policy hardened)     ImageMagick policy hardened)    open_basedir (/usr/share/...)
        │                                │                                │
        └────────────────────────────────┼────────────────────────────────┘
                                         ▼
                MariaDB Server (Unix Socket + 32-Bit Hashed DB Users)
                                         ▲
                Redis Object Cache (Loopback Bind | SHA-256 ACL | default OFF)
                [~site_a_xxxx:*]  ◀── Zero Cross-Tenant Access ──▶  [~site_b_yyyy:*]
```

---

## 📂 Repository Structure

```text
bashboard/
├── bashboard.sh                    # Core TUI Monitor, Trusted Module Dispatcher & Event Loop (v1.9.1)
├── README.md                       # Systems Architecture & Operator Manual
└── scripts/                        # Modular Workload Engines
    ├── 01_install_lemp.sh          # [1] LEMP, SHA-256 Redis ACLs, SHA-512 WP-CLI, ImageMagick & PMA
    ├── 02_create_vhost.sh          # [2] VHost Deployer (32-Bit Hash, Root ACME, Root Slowlog, ACL)
    ├── 03_wordpress_manager.sh     # [3] WP Manager (Zero-Root-Write Tenant Ops, FD-Locked Cron)
    ├── 04_harden_security.sh       # [4] DevSecOps Hardening (ssh.socket Union, F2B ignoreip, UFW)
    ├── 06_log_optimizer.sh         # [6] 3-Tier Logrotate Optimizer (Octal-Safe & CVE-2016-1247 Safe)
    ├── 07_delete_vhost.sh          # [7] Atomic 8-Tier Tenant, Slowlog & Live Redis ACL Purge Engine
    └── 12_backup_gdrive.sh         # [12] Per-Site Streaming Backup Engine (Min-Keep & Config Tar)
```

*(Note: Dashboard slots `[5]`, `[10]`, `[11]`, and `[13]` are reserved extension points displayed as `(n/a)` until custom workload scripts are added to `scripts/`.)*

---

## 🚀 Modular Engine Details

### `[0]` Core TUI & Dispatcher (`bashboard.sh`)
* **Zero-Trust Module Verification:** Refuses to execute any script inside `scripts/` unless it is a regular non-symlink file owned by `root` with zero group/world write bits (`(mode & 022) == 0`).
* **Clean EOF & FD 200 Handling:** Distinguishes `read -t 60` timeouts (`exit > 128`) from closed-stdin `EOF` (`exit 1`) to prevent infinite CPU spin loops, closes lock descriptor `200>&-` in both child modules and the background IP resolver, auto-expires failed IP cache entries after 5 minutes, and excludes `catchall.crt` from the Dual SSL Sensor.

### `[1]` LEMP Stack, Redis ACL & phpMyAdmin Provisioner (`01_install_lemp.sh`)
* **Strict Subshell `run_task()`:** Executes every provisioning function inside an independent `( set -Eeuo pipefail; "$@" )` subshell so `set -e` is never neutralized by `if "$@"`—preventing broken configs (`php-fpm -t` or `nginx -t`) from restarting live services.
* **Smart Dual-OS Repository Resolver:** Supports Ubuntu `22.04`/`24.04`/`26.04 LTS` and Debian `11`/`12`/`13`. Only adds Ondrej PPA or Sury GPG keyrings if the requested PHP version is absent from native APT repos, and handles PHP `8.5+` built-in `opcache` dynamically with `DPkg::Lock::Timeout=60`.
* **CIDR-Guarded Cloudflare Real-IP & Shared Root ACME Webroot:** Preserves existing synced `00-cloudflare-realip.conf` ranges on re-runs, validates downloaded IPv4/IPv6 CIDRs against overbroad wildcards (`0.0.0.0/0`..`/7`, `::/0`..`/15`) in `/usr/local/bin/bashboard-update-cf-ips`, and initializes `/var/www/_acme-challenge` (`0755 root:root`).
* **Zero-Leak MariaDB Provisioning:** Configures dual authentication (`unix_socket OR mysql_native_password`) via `stdin` Heredoc and `MYSQL_PWD` with SQL escaping—never leaking root passwords in `/proc` or logs (`0600`).
* **ImageMagick `policy.xml` Hardening:** Disables dangerous coders (`EPHEMERAL`, `URL`, `HTTPS`, `HTTP`, `FTP`, `MVG`, `MSL`, `TEXT`, `LABEL`, `PS`, `EPS`, `PDF`, `XPS`) across `/etc/ImageMagick-*/policy.xml`.
* **SHA-256 ACL-Isolated Redis Engine:** Explicitly binds loopback (`bind 127.0.0.1` / `-::1`), enforces `protected-mode yes`, `supervised systemd`, and `maxmemory-policy allkeys-lru`, disables infrastructure commands globally (`KEYS`, `MONITOR`, `CONFIG`, `SHUTDOWN`, `DEBUG`, `BGSAVE`, `SAVE`, `SLAVEOF`, `REPLICAOF`), disables `user default off`, and stores **SHA-256 password hashes (`#<64-hex>`)** in `/etc/redis/users.acl` (`0640 redis:redis`) while preserving `bashboard_admin` credentials in `/etc/bashboard/redis-admin.cred` (`0600`).
* **SHA-512 Verified WP-CLI:** Downloads both `wp-cli.phar` and `wp-cli.phar.sha512`, verifies the 128-hex digest via `sha512sum -c`, and smoke-tests the PHAR strictly as unprivileged `nobody`.
* **Hardened Loopback phpMyAdmin (`127.0.0.1:8080`):** Installs without Apache bloat, places `location ~ /\.` and `location ~* ^/(?:libraries|setup|templates|locale|sql)` **strictly above** `location ~ \.php$` (guaranteeing `403 Forbidden` on `/setup/index.php`), applies `wplogin` rate limiting, validates `php-fpm -t` before restarting, and isolates execution under `v_pma_sys`.

### `[2]` Virtual Host & Tenant Provisioner (`02_create_vhost.sh`)
* **32-Bit SHA-256 Collision-Resistant Identifiers & Hard Abort:** Generates 8-hex SHA-256 hashes for tenant user (`v_${slug:0:12}_${sha8}`), FPM pool (`${slug:0:20}_${sha8}`), DB (`${slug:0:20}_${sha8}`), and DB user (`u_${slug:0:12}_${sha8}`), and **aborts before provisioning** if the Linux user, group, pool, DB, or DB user already exists (never silently reusing UIDs).
* **Atomic `set -E` Rollback:** Runs with `set -Eeuo pipefail` (`errtrace`) and explicitly invokes `rollback_on_failure` on `nginx -t` failure so broken configs never stay linked in `sites-enabled`.
* **Per-Tenant SHA-256 Redis ACLs (Left-to-Right Safe):** Appends `user ${t_user} on #${sha256} ~${prefix}* -@all +@read +@write +@keyspace +@transaction +auth +quit +ping +echo +select +hello -@dangerous -@admin -flushall -flushdb -keys +info` to `/etc/redis/users.acl`, live-loads via `ACL LOAD`, and injects `WP_REDIS_*` constants into `wp-config.php` (`0600`) via environment substitution (zero `/proc` exposure, with `--skip-check` + live `MYSQL_PWD` verification).
* **3-Tier Symlink-Immune Logging & Root-Owned ACME Webroot:**
  * `/var/www/$DOMAIN`: `root:$vhost_user` (`0750`) with `www-data` in group `$vhost_user`.
  * `/var/www/$DOMAIN/logs`: `www-data:$vhost_user` (`0750`) — Nginx logs (`nginx_*.log`, `uploads_*.log`) are non-writable by the tenant.
  * `/var/www/$DOMAIN/logs/php`: `$vhost_user:$vhost_user` (`0750`) — PHP-FPM worker `error_log` rotates cleanly via `su $vhost_user $vhost_user`.
  * `/var/log/php-fpm/${pool_name}_slow.log`: `root:root` (`0640` inside `0750 root:root`) — isolates the root-written FPM master `slowlog` completely outside tenant control.
  * `/var/www/_acme-challenge`: Shared root-owned (`0755 root:root`) ACME webroot so Certbot renewals never write as `root` inside `public_html`.
  * `/etc/bashboard/sites/${DOMAIN}.state`: Root-owned (`0600`) metadata manifest (stores identifiers only—never plaintext passwords).
* **Hardened PHP Pool & Nginx VHost:** Disables `exec`, `passthru`, `shell_exec`, `system`, `proc_open`, `popen`, `pcntl_exec`, `pcntl_fork`, `pcntl_signal`, `pcntl_alarm`, `dl`, `putenv`, `show_source`, `highlight_file`, `proc_get_status`, `opcache_get_status`, `opcache_get_configuration`, `posix_kill`, `posix_mkfifo`, `posix_setpgid`, `posix_setsid`, `posix_setuid`, `posix_geteuid`, `posix_getpwuid`. Deploys the HTTP `444` catch-all block, blocks PHP in uploads while preserving nested `expires 30d` caching & security headers, redirects `http://uploads.$DOMAIN` cleanly to `https://uploads.$DOMAIN`, tags `/etc/hosts` lines with `# bashboard-vhost:$DOMAIN`, and installs the injection-safe `/usr/local/bin/domain` switcher.

### `[3]` WordPress Site Manager (`03_wordpress_manager.sh`)
* **Zero-Root-Write Tenant Operations (Symlink LPE Immune):** Never runs `mkdir`/`chown` as `root` inside tenant-writable `tmp/` or `public_html/`. `wp_run()` validates `tmp/` is not a symlink and creates `tmp/wp-cache` strictly as `runuser -u "$u"`; Options `[2]` (`.maintenance`) and `[7]` (`WP_DEBUG` fallback `sed` + `chmod 600`) execute strictly as `runuser -u "$v_u"`; `enforce_permissions()` uses physical non-dereferencing `chown -h -P -R`.
* **SHA-512 Verified WP-CLI & FD-Locked Multi-PHP Cron:** Verifies WP-CLI via official `.sha512` and runs smoke tests as `nobody`. Passes `PHP_VER` explicitly from root-owned `/etc/cron.d/bashboard-wp-*` into `/usr/local/bin/bashboard-cron-runner` (`exec 9>"$LOCK_FILE"; flock -n 9`) with `TMPDIR` and `-d sys_temp_dir` sandboxed to `/var/www/$DOMAIN/tmp`.

### `[4]` DevSecOps Hardening Engine (`04_harden_security.sh`)
* **Ubuntu 24.04+ `ssh.socket` & Live Session Port Union:** Aggregates SSH ports from the live `$SSH_CONNECTION` destination port, active `ssh.socket` `Listen` properties (`systemctl show -p Listen`), listening `ss -tlnp` sockets (`sshd`/`ssh.socket`), and `sshd -T` (when `ssh.socket` is inactive)—eliminating socket-activation UFW lockouts.
* **SSH-Reachable Dual Anti-Lockout Sentinel:** Only allows `PermitRootLogin no` if a non-root sudoer has a valid login shell **and** is SSH-reachable (has `~/.ssh/authorized_keys` or an unlocked `/etc/shadow` password while `PasswordAuthentication != no`).
* **Operator-Safe Fail2Ban & Allow-First UFW:** Configures `ignoreip = 127.0.0.1/8 ::1 <OPERATOR_IP>` (toggleable via `[6]`), sets `maxretry = 5` (preventing multi-key `ssh-agent` self-bans), validates syntax with `fail2ban-client -t`, verifies `systemctl is-active fail2ban`, and opens UFW allow rules **before** applying `default deny incoming`.

### `[6]` Log Rotation Optimizer (`06_log_optimizer.sh`)
* **3-Tier Sync & Octal-Safe Arithmetic:** Synchronizes Nginx (`logs/`), Worker PHP (`logs/php/` + legacy v1.8 flat `logs/php_*.log` fallback), and Root Master Slowlog (`/var/log/php-fpm/`) drop-ins, uses base-10 arithmetic (`10#`) so inputs like `08`/`09` never crash, and defaults `Force Rotate & Vacuum` (`[3]`) to `OFF` so routine policy syncs do not burn log history.

### `[7]` Virtual Host Purge Engine (`07_delete_vhost.sh`)
* **Resilient 8-Tier Dismantling:** Filters out `html` and `_acme-challenge`, enforces strict FQDN validation before any `rm -rf`, never aborts mid-purge if Nginx is inactive or `reload` warns, revokes Redis ACLs live (preserving `redis:redis 0640`), removes `/var/log/php-fpm/*_slow.log*`, removes tagged `# bashboard-vhost:$TARGET_SITE` `/etc/hosts` entries, and reports `DROP DATABASE` failures explicitly instead of swallowing them.

### `[12]` Automated Google Drive Backup Engine (`12_backup_gdrive.sh`)
* **Fail-Loud Guard & Minimum Snapshot Retention (`MIN_KEEP_SNAPSHOTS=3`):** Increments `FAILED_COUNT` if any site with `public_html` lacks a valid root-owned `.state` file (or a WordPress site has empty/invalid `DB_NAME`), immediately blocking remote pruning. When pruning runs (`UPLOADED_COUNT > 0 && FAILED_COUNT == 0`), the newest `MIN_KEEP_SNAPSHOTS` folders are **always preserved regardless of age**, and zero-artifact runs exit non-zero instead of reporting false success.
* **Per-Site Streaming + Control-Plane Config Archive:** Streams each site's `.sql.gz` and `.tar.gz` and immediately frees local staging space, plus archives `/etc/bashboard/sites`, `/etc/bashboard/backup.conf`, Nginx vhosts/`conf.d`, FPM pools, logrotate drop-ins, and Bashboard crons into `server_configs_<ts>.tar.gz`. Tier-2 DB fallback reads credentials via sandboxed `wp config get` (zero root `chown` inside `tmp/`) and dumps via `MYSQL_PWD` supporting host, port, and socket syntax.

---

## 🗺️ System Footprint & Generated Files Matrix

| File / Directory Path | Created By | Purpose & Lifecycle |
| :--- | :--- | :--- |
| `/etc/bashboard/sites/*.state` | `02` / `07` | Root-owned (`0600`) metadata manifests (never stores plaintext passwords). |
| `/etc/bashboard/redis-admin.cred` | `01` | Root-owned (`0600`) Redis ACL admin credentials (`bashboard_admin`). |
| `/etc/bashboard/backup.conf` | `12` | Root-owned (`0600`) persistent backup, retention & `MIN_KEEP_SNAPSHOTS` settings. |
| `/etc/redis/users.acl` | `01` / `02` / `07` | Redis ACL file (`0640 redis:redis`) storing SHA-256 `#<hash>` per-tenant rules. |
| `/var/www/_acme-challenge/` | `01` / `02` | Shared root-owned (`0755`) ACME HTTP-01 webroot (immune to tenant symlinks). |
| `/var/log/php-fpm/*_slow.log` | `02` / `07` | Root-owned (`0640` in `0750 root:root`) FPM master slowlogs. |
| `/run/bashboard.lock` | `bashboard.sh` | Exclusive `flock` (FD 200) preventing concurrent dashboard sessions. |
| `/run/bashboard_backup.lock` | `12_backup_gdrive.sh` | Exclusive `flock` (FD 201) preventing concurrent manual and cron backups. |
| `/run/bashboard_ip` | `bashboard.sh` | Cached public IPv4 (kernel NICs first, 300s auto-expiry on failed lookups). |
| `/var/log/bashboard*.log` | `core` / `01` / `02` / `12` | Root-restricted (`0600`) audit, install, SSL, and nightly backup logs. |
| `/usr/local/bin/wp` | `01` / `03` | SHA-512 verified WP-CLI PHAR binary (`0755`). |
| `/usr/local/bin/domain` | `02_create_vhost.sh` | Hardened CLI helper to enter a site's isolated tenant shell (`domain <site>`). |
| `/usr/local/bin/bashboard-update-cf-ips` | `01_install_lemp.sh` | CIDR-validated Cloudflare Real-IP synchronizer (monthly cron). |
| `/usr/local/bin/bashboard-cron-runner` | `03_wordpress_manager.sh` | FD-locked, Multi-PHP, `TMPDIR`-sandboxed WP-Cron & Action Scheduler runner. |
| `/etc/nginx/conf.d/00-cloudflare-realip.conf` | `01_install_lemp.sh` | Cloudflare IPv4/IPv6 ranges (`CF-Connecting-IP`). |
| `/etc/nginx/conf.d/00-bashboard-rate-limit.conf` | `01` / `02` | Global Nginx `limit_req_zone` (`wplogin`, 10 req/min, HTTP 429). |
| `/etc/nginx/conf.d/00-bashboard-default-catchall.conf` | `02_create_vhost.sh` | Default catch-all server dropping unknown Host headers with HTTP `444`. |
| `/etc/nginx/conf.d/00-bashboard-phpmyadmin.conf` | `01_install_lemp.sh` | Loopback-only (`127.0.0.1:8080`) rate-limited Nginx listener for phpMyAdmin. |
| `/etc/php/X.Y/fpm/pool.d/phpmyadmin.conf` | `01_install_lemp.sh` | Isolated PHP-FPM pool (`v_pma_sys`) with zero `/var/www/*` access. |
| `/etc/ImageMagick-*/policy.xml` | `01_install_lemp.sh` | Hardened ImageMagick policy blocking delegate/Ghostscript RCE coders. |
| `/etc/sysctl.d/99-bashboard-security.conf` | `04_harden_security.sh` | Kernel network and VFS security parameters. |
| `/etc/ssh/sshd_config.d/00-bashboard-hardening.conf` | `04_harden_security.sh` | First-match OpenSSH daemon hardening directives. |
| `/etc/fail2ban/jail.d/00-bashboard.conf` | `04_harden_security.sh` | SSH intrusion prevention rules (`ignoreip`, `maxretry=5`, `ufw` banaction). |
| `/etc/systemd/journald.conf.d/99-bashboard-limits.conf` | `06_log_optimizer.sh` | Systemd journal storage ceiling configuration. |
| `/etc/cron.d/bashboard-*` | `01` / `03` / `12` | Automated Cloudflare IP sync, 5m per-site WP-Cron, and 03:00 AM backup jobs. |

---

## 🛠️ Installation & Quickstart

### System Requirements
* **Operating System:** Ubuntu 22.04 / 24.04 / 26.04 LTS or Debian 11 / 12 / 13
* **Privileges:** Root access (`sudo -i`)
* **Terminal Geometry:** 95+ Columns recommended

```bash
# 1. Switch to root and clone the repository into /opt/
sudo -i
cd /opt
git clone https://github.com/HamxaBoustani/bashboard.git
cd bashboard

# 2. Enforce strict root-only permissions (required by Bashboard's trusted module loader)
chown -R root:root /opt/bashboard
chmod 700 bashboard.sh scripts/*.sh

# 3. Verify Bash syntax across all modules
bash -n bashboard.sh scripts/*.sh

# 4. Launch Bashboard Control Engine
./bashboard.sh
```

---

## ⚙️ Operator Configuration Guides

### 1. Navigating & Editing Site Files (`domain` Helper)
```bash
# List isolated virtual hosts:
domain

# Enter a site's isolated tenant shell (supports Tab auto-completion):
domain example.com
```
You are placed inside `/var/www/example.com/public_html` running strictly under that site's tenant user with `TMPDIR=/var/www/example.com/tmp`. Type `exit` to return.

### 2. Accessing Sandboxed phpMyAdmin (`127.0.0.1:8080`)
Run on your **local workstation**:
```bash
ssh -L 8081:127.0.0.1:8080 your_ssh_user@YOUR_SERVER_IP
```
Open `http://localhost:8081` in your local browser and log in with any site's database credentials (from `wp-config.php` or the Module `[2]` summary) or your MariaDB administrative account.

### 3. Google Drive Off-Site Backup Setup (`rclone` + Recommended E2EE)
> ⚠️ Always run `sudo rclone config` as **root** so config saves to `/root/.config/rclone/rclone.conf`.

1. Run `sudo rclone config` -> `n` (New remote) -> Name: **`bashboard-gdrive`** -> Storage: **`drive`**.
2. Leave `client_id` & `client_secret` blank (Press `Enter`; do **not** type `n`) unless using your own Google Cloud OAuth credentials.
3. Choose scope **`1`**, skip root folder/service account/advanced config, choose **`n`** for auto browser auth, authorize via `rclone authorize "drive"` on your local computer, paste the JSON token, and save.
4. Verify connection:
   ```bash
   sudo rclone lsd bashboard-gdrive:
   ```
5. Launch `./bashboard.sh` -> **`[12]`** -> set retention (`[4]`), run an immediate test (`[9]`), and install the 03:00 AM nightly cron (`[8]`). Settings persist in `/etc/bashboard/backup.conf`.

> 🔐 **Strongly Recommended (Client-Side Encryption via `rclone crypt`):**
> Because web archives contain `wp-config.php` and database dumps contain user data, wrap your Google Drive remote with `rclone crypt` (e.g., create remote `bashboard-gdrive-crypt` pointing to `bashboard-gdrive:bashboard-encrypted`), then set `RCLONE_REMOTE=bashboard-gdrive-crypt` inside `/etc/bashboard/backup.conf`.

### 4. Static Media Subdomain (`uploads.domain.com`)
When Option `[4] Uploads Subdomain` is enabled in Module `[2]`:
1. Point `uploads.example.com` DNS (`A` or `CNAME`) to your VPS before running Module `[2]`.
2. Add `define( 'UPLOADS', 'uploads' );` to `wp-config.php` above `/* That's all, stop editing! */` (and optionally set `upload_url_path` to `https://uploads.example.com`).

### 5. Cloudflare & DNS Pre-Flight Note
Keep new domains set to **DNS Only (Grey Cloud)** while running Module `[2]` so public DNS verification passes. Once Let's Encrypt binds, switch back to **Proxied (Orange Cloud)** with SSL/TLS mode set to **Full (Strict)**.

---

## 📋 Recommended Provisioning Workflow

```text
[Step 1] Option [1]  -> Provision LEMP Stack (Nginx, MariaDB, PHP-FPM, SHA-256 Redis ACL, WP-CLI, PMA)
[Step 2] Option [4]  -> Enforce Security Hardening (ssh.socket UFW, Fail2Ban ignoreip, Sysctl, SSH)
[Step 3] Option [2]  -> Deploy Virtual Host (32-Bit Hash Tenant, Root ACME, Root Slowlog, Redis ACL)
[Step 4] Option [3]  -> WordPress Manager (Enable 5m Multi-PHP System WP-Cron, Verify Checksums)
[Step 5] Option [6]  -> Log Optimizer (Sync 3-Tier Logrotate Policies & Cap Journald)
[Step 6] Option [12] -> Configure Google Drive Backup (Verify rclone & Enable 03:00 AM Cron)
```

---

## 🔍 Verification & Security Audit Cheat Sheet

```bash
# 1. Verify Root-Anchored POSIX, 3-Tier Logging & Root ACME Webroot
sudo ls -ld /var/www/example.com /var/www/example.com/logs /var/www/example.com/logs/php /var/log/php-fpm /var/www/_acme-challenge
# Expected:
# drwxr-x--- root     v_example_com_xxxxxxxx  /var/www/example.com
# drwxr-x--- www-data v_example_com_xxxxxxxx  /var/www/example.com/logs
# drwxr-x--- v_example_com_xxxxxxxx v_example_com_xxxxxxxx  /var/www/example.com/logs/php
# drwxr-x--- root     root                    /var/log/php-fpm
# drwxr-xr-x root     root                    /var/www/_acme-challenge

# 2. Verify CVE-2016-1247 Immunity & Working 3-Tier Logrotate
sudo -u v_example_com_xxxxxxxx ln -s /etc/passwd /var/www/example.com/logs/nginx_error.log   # Must fail: Permission denied
sudo logrotate -f /etc/logrotate.d/vhost-example.com                                        # Must exit 0 cleanly

# 3. Verify SHA-256 Redis ACL Isolation
redis-cli PING                                                                              # Must return: NOAUTH
sudo bash -c 'source /etc/bashboard/redis-admin.cred && REDISCLI_AUTH="$REDIS_ADMIN_PASS" redis-cli --user "$REDIS_ADMIN_USER" PING'
# Expected: PONG (and /etc/redis/users.acl contains #<64-hex> hashes, never plaintext passwords)

# 4. Verify phpMyAdmin /setup/index.php Block, Uploads PHP Denial & XML-RPC Block
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/setup/index.php              # Must return: 403
curl -k -s -o /dev/null -w "%{http_code}\n" https://example.com/xmlrpc.php                  # Must return: 403

# 5. Verify ImageMagick Hardening & Dashboard EOF Safety
grep -E 'pattern="(EPHEMERAL|MVG|PDF|PS)"' /etc/ImageMagick-*/policy.xml
sudo /opt/bashboard/bashboard.sh </dev/null && echo "✅ CLEAN EOF EXIT"
```

---

## 🚨 Troubleshooting & Disaster Recovery

### 1. Manual Site Restoration from Google Drive Backup
Because `logs/` and `tmp/` are excluded from web archives to avoid bloat, recreate the empty runtime directories after extracting a backup:
```bash
# 1. List available snapshots & download a site's archive + DB dump
sudo rclone lsd bashboard-gdrive:bashboard-backups/
sudo rclone copy bashboard-gdrive:bashboard-backups/<TIMESTAMP>/ /tmp/restore/

# 2. Provision the target site first via Module [2] (creates tenant user, FPM pool, Redis ACL & logs/tmp),
#    then extract web payload and import database:
sudo tar -xzf /tmp/restore/example.com_web_<TIMESTAMP>.tar.gz -C /var/www/
sudo mkdir -p /var/www/example.com/logs/php /var/www/example.com/tmp
# Re-sync permissions via Module [3] (or Module [6] for logs), then import SQL:
gunzip -c /tmp/restore/example.com_db_<TIMESTAMP>.sql.gz | sudo mariadb -u root <DB_NAME>
sudo rm -rf /tmp/restore
```

### 2. `rclone` Error: `couldn't fetch token: invalid_client`
```bash
sudo sed -i '/^client_id/d; /^client_secret/d' /root/.config/rclone/rclone.conf
sudo rclone lsd bashboard-gdrive:
```

### 3. Let's Encrypt Pre-Flight Skipped or Rate-Limited
Switch Cloudflare to **DNS Only (Grey Cloud)** and issue via the root-owned ACME webroot:
```bash
sudo certbot certonly --webroot -w /var/www/_acme-challenge \
  --cert-name example.com --non-interactive --agree-tos \
  --register-unsafely-without-email \
  -d example.com -d www.example.com && \
sudo sed -i "s|/etc/nginx/ssl/example\.com\.crt|/etc/letsencrypt/live/example.com/fullchain.pem|g" /etc/nginx/sites-available/example.com && \
sudo sed -i "s|/etc/nginx/ssl/example\.com\.key|/etc/letsencrypt/live/example.com/privkey.pem|g" /etc/nginx/sites-available/example.com && \
sudo rm -f /etc/nginx/ssl/example.com.crt /etc/nginx/ssl/example.com.key && \
sudo nginx -t && sudo systemctl reload nginx
```

### 4. `502 Bad Gateway` Outage
```bash
sudo tail -n 20 /var/www/example.com/logs/nginx_error.log
sudo tail -n 20 /var/www/example.com/logs/php/php_error.log
sudo tail -n 20 /var/log/php-fpm/example_com_*_slow.log
sudo ls -la /run/php/php*-fpm-example_com_*.sock
for fpm in /usr/sbin/php-fpm*; do sudo "$fpm" -t; done
```

### 5. WordPress White Screen of Death (WSOD)
Launch `./bashboard.sh` -> **`[3] WordPress Manager`** -> Select domain -> **`[6] 🚨 Deactivate ALL Plugins (WSOD Fix)`**.

---

## 🤝 Contributing & Extending Modules

1. Fork the repository.
2. Add custom workload scripts into `scripts/` following `scripts/XX_module_name.sh`.
3. Enforce strict mode (`set -euo pipefail`), explicit root check (`[ "$EUID" -ne 0 ]`), root ownership (`chown root:root`), and `chmod 700`.
4. Never run `chown`/`mkdir`/file writes as `root` inside tenant-writable paths (`/var/www/$DOMAIN/public_html` or `tmp/`).
5. Submit a Pull Request.

---

## 📜 License
Licensed under the **MIT License**. Engineered for production bare-metal and cloud Linux VPS nodes.