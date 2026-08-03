# Fail2ban Configuration for Docker Homelab

This directory contains fail2ban configuration files for protecting Nginx-proxied Docker services.

## Architecture

**Deployment:** Host-based (not containerized)

**Why host-based?**
- ✅ Lower overhead (no Docker-in-Docker)
- ✅ Blocks traffic BEFORE it reaches Docker (DOCKER-USER iptables chain)
- ✅ No privileged container required
- ✅ Protects all Docker services simultaneously

## Active Jails (6 total)

| Jail | Protection | Log Source | Threshold | Ban Duration |
|------|------------|------------|-----------|--------------|
| `nginx-4xx` | 403/404 responses (probing/forbidden) | nginx access.log | 3 in 10min | 24 hours |
| `nginx-malicious-uri` | Vulnerability scans (wp-admin, .env, etc.) | nginx access.log | 3 in 10min | 24 hours |
| `homeassistant-auth` | Failed HA logins | home-assistant.log | 3 in 10min | 1 hour |
| `seafile-auth` | Failed Seafile logins (400/403) | nginx access.log | 10 in 10min | 24 hours |
| `immich-auth` | Failed Immich password logins (401 on `/api/auth/login`) | nginx access.log | 5 in 10min | 24 hours |
| `recidive` | Repeat offenders | fail2ban.log | 3 bans in 24h | 1 week |

### Why These Jails?

**nginx-4xx** catches:
- Access denied (403 Forbidden)
- Path probing (404 Not Found)

> **⚠️ 401 is deliberately NOT matched here.** A 401 Unauthorized is the *normal*
> response any legitimate client gets when its session token expires. On cold
> start the Immich and Home Assistant iOS apps fire a burst of API calls
> (`/api/users/me`, `/api/sync/ack`, `/api/assets/.../thumbnail`, …) that all
> return 401 until the app re-authenticates. The old filter matched 401 and
> banned the phone's public (Telekom) IP within one second — *after* a
> successful SSO login — which looked exactly like "login doesn't work". Real
> credential brute-force is handled by the dedicated per-service auth jails
> (`homeassistant-auth`, `seafile-auth`, `immich-auth`) instead.

**nginx-malicious-uri** catches attackers probing for:
- WordPress: `wp-admin`, `wp-login`, `xmlrpc.php`
- Database tools: `phpmyadmin`, `mysql`, `adminer`
- Config exposure: `.env`, `.git`, `config`, `backup`
- Backdoors: `shell`, `setup`, `install`

> **Note:** `/api/ios/`, `/api/config/`, `/api/brands/` (Home Assistant) and
> `/api/server/` (Immich) paths are explicitly ignored. They legitimately
> contain keywords like `config`, `backup`, `install` that would otherwise
> match the malicious-uri filter. In particular Immich polls
> `/api/server/config` on every app start.

**homeassistant-auth** is special:
- Home Assistant returns HTTP 200 even for failed logins
- Must monitor HA's internal log instead of nginx

**seafile-auth** monitors Seafile's login flow (400/403 on `/api2/auth-token/`
and `/accounts/login/`); higher `maxretry` because 2FA generates 2× 400 per
attempt.

**immich-auth** monitors *only* `POST /api/auth/login` → 401 (wrong password).
It is intentionally narrow so it never fires on the expired-token 401 burst
described above. Note: this deployment is SSO-only (Google OIDC), so the real
password check happens at the identity provider — this jail mainly guards the
local login endpoint against probing/brute-force should it ever be enabled.

**recidive** - the "three strikes" rule:
- Monitors fail2ban's own log
- If an IP gets banned 3 times → 1 week ban

## File Structure

```
fail2ban/
├── filter.d/
│   ├── nginx-4xx.conf              # 403/404 responses (probing)
│   ├── nginx-malicious-uri.conf    # Vulnerability scan patterns
│   ├── immich-auth.conf            # Immich login failures (401 on /api/auth/login)
│   └── homeassistant-auth.conf     # HA login failures
│
├── jail.d/
│   ├── nginx.local                 # nginx-4xx + seafile-auth + immich-auth + nginx-malicious-uri
│   ├── homeassistant.local         # homeassistant-auth
│   └── recidive.local              # Repeat offender protection
│
├── jail.local                      # sshd jail disabled
├── fail2ban-status.sh              # Status overview script
└── fail2ban-motd.sh                # Login banner script
```

## Deployment

Config lives in this git repo and is pulled onto the Raspberry Pi, then copied
into `/etc/fail2ban/` (the daemon reads its config from there, not from the
repo). The copy step is required after every `git pull` that touches fail2ban.

### Initial Setup

```bash
# 0. Get the latest config onto the Pi
cd ~/docker && git pull

# 1. Copy configurations
sudo cp fail2ban/filter.d/nginx-4xx.conf /etc/fail2ban/filter.d/
sudo cp fail2ban/filter.d/nginx-malicious-uri.conf /etc/fail2ban/filter.d/
sudo cp fail2ban/filter.d/immich-auth.conf /etc/fail2ban/filter.d/
sudo cp fail2ban/filter.d/homeassistant-auth.conf /etc/fail2ban/filter.d/
sudo cp fail2ban/jail.d/*.local /etc/fail2ban/jail.d/
sudo cp fail2ban/jail.local /etc/fail2ban/jail.local

# 2. Install helper scripts
sudo cp fail2ban/fail2ban-status.sh /usr/local/bin/fail2ban-status
sudo cp fail2ban/fail2ban-motd.sh /usr/local/bin/fail2ban-motd
sudo chmod +x /usr/local/bin/fail2ban-status /usr/local/bin/fail2ban-motd

# 3. Test and activate
sudo fail2ban-client -t
sudo systemctl restart fail2ban

# 4. Verify
sudo fail2ban-client status
```

**Expected output:**
```
Status
|- Number of jail:      6
`- Jail list:   homeassistant-auth, immich-auth, nginx-4xx, nginx-malicious-uri, recidive, seafile-auth
```

### Updates (After Config Changes)

```bash
# Pull the repo first, then sync into /etc/fail2ban and reload
cd ~/docker && git pull
sudo cp fail2ban/filter.d/*.conf /etc/fail2ban/filter.d/
sudo cp fail2ban/jail.d/*.local /etc/fail2ban/jail.d/
sudo fail2ban-client -t && sudo systemctl reload fail2ban
```

## Monitoring

### Quick Status (Recommended)

```bash
sudo fail2ban-status
```

**Example output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Fail2ban Status Overview
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

JAIL                      BANNED   FAILED  TOTAL BAN TOTAL FAIL
─────────────────────────────────────────────────────────────────
✓ homeassistant-auth          0        0          0          0
⚠ nginx-4xx                   1        0         10         70
⚠ nginx-malicious-uri         3        0         11         77
✓ recidive                    0        4          0         15
─────────────────────────────────────────────────────────────────
TOTAL (4 jails)               4        4

⚠ 4 IP(s) currently banned

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Verbose mode (shows banned IPs):**
```bash
sudo fail2ban-status --verbose
```

### Native Commands

```bash
# Check all jails
sudo fail2ban-client status

# Check specific jail
sudo fail2ban-client status nginx-4xx

# View all banned IPs
sudo fail2ban-client banned

# Unban an IP
sudo fail2ban-client unban <IP_ADDRESS>

# Live log monitoring
sudo tail -f /var/log/fail2ban.log
```

### Test Filters

```bash
# Test nginx-4xx filter
sudo fail2ban-regex /home/stefan/docker/proxy/nginx/logs/access.log \
  /etc/fail2ban/filter.d/nginx-4xx.conf

# Test malicious URI filter
sudo fail2ban-regex /home/stefan/docker/proxy/nginx/logs/access.log \
  /etc/fail2ban/filter.d/nginx-malicious-uri.conf

# Test HA auth filter
sudo fail2ban-regex /home/stefan/docker/homeassistant/homeassistant/config/home-assistant.log \
  /etc/fail2ban/filter.d/homeassistant-auth.conf
```

## Login Banner (Optional)

Show fail2ban status on SSH login:

```bash
echo 'sudo /usr/local/bin/fail2ban-motd' >> ~/.bashrc
```

*Only displays when there are banned IPs or failed attempts.*

## Important Notes

### Log Paths
- **Nginx:** `/home/stefan/docker/proxy/nginx/logs/access.log`
- **Home Assistant:** `/home/stefan/docker/homeassistant/homeassistant/config/home-assistant.log`

### Ignored Networks
All jails ignore private networks:
- `127.0.0.1/8` (localhost)
- `192.168.0.0/16`, `172.16.0.0/12`, `10.0.0.0/8` (RFC1918)

### iptables Chain
All jails target `DOCKER-USER` chain - bans are applied BEFORE Docker routing.

## Troubleshooting

### Jail Not Starting
```bash
sudo journalctl -u fail2ban -n 50
```

### Filter Not Matching
```bash
sudo fail2ban-regex /path/to/log /etc/fail2ban/filter.d/filter.conf --print-all-matched
```

### Accidentally Banned
```bash
sudo fail2ban-client unban YOUR_IP
```

## Future: CrowdSec Migration

Consider migrating to [CrowdSec](https://www.crowdsec.net/) for:
- Crowd-sourced blocklists (proactive blocking)
- Modern YAML scenarios instead of regex
- Community-maintained detection rules

