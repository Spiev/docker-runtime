# Fail2ban Configuration for Docker Homelab

This directory contains fail2ban configuration files for protecting Nginx-proxied Docker services.

## Architecture

**Deployment:** Host-based (not containerized)

**Why host-based?**
- ✅ Lower overhead (no Docker-in-Docker)
- ✅ Blocks traffic BEFORE it reaches Docker (DOCKER-USER iptables chain)
- ✅ No privileged container required
- ✅ Protects all Docker services simultaneously

## Active Jails (4 total)

| Jail | Protection | Log Source | Threshold | Ban Duration |
|------|------------|------------|-----------|--------------|
| `nginx-4xx` | 401/403/404 responses | nginx access.log | 3 in 10min | 24 hours |
| `nginx-malicious-uri` | Vulnerability scans (wp-admin, .env, etc.) | nginx access.log | 3 in 10min | 24 hours |
| `homeassistant-auth` | Failed HA logins | home-assistant.log | 3 in 10min | 1 hour |
| `recidive` | Repeat offenders | fail2ban.log | 3 bans in 24h | 1 week |

### Why These 4 Jails?

**nginx-4xx** catches:
- Authentication failures (401 Unauthorized)
- Access denied (403 Forbidden)
- Path probing (404 Not Found)

**nginx-malicious-uri** catches attackers probing for:
- WordPress: `wp-admin`, `wp-login`, `xmlrpc.php`
- Database tools: `phpmyadmin`, `mysql`, `adminer`
- Config exposure: `.env`, `.git`, `config`, `backup`
- Backdoors: `shell`, `setup`, `install`

**homeassistant-auth** is special:
- Home Assistant returns HTTP 200 even for failed logins
- Must monitor HA's internal log instead of nginx

**recidive** - the "three strikes" rule:
- Monitors fail2ban's own log
- If an IP gets banned 3 times → 1 week ban

## File Structure

```
fail2ban/
├── filter.d/
│   ├── nginx-4xx.conf              # 401/403/404 responses
│   ├── nginx-malicious-uri.conf    # Vulnerability scan patterns
│   └── homeassistant-auth.conf     # HA login failures
│
├── jail.d/
│   ├── nginx.local                 # nginx-4xx + nginx-malicious-uri
│   ├── homeassistant.local         # homeassistant-auth
│   └── recidive.local              # Repeat offender protection
│
├── jail.local                      # sshd jail disabled
├── fail2ban-status.sh              # Status overview script
└── fail2ban-motd.sh                # Login banner script
```

## Deployment

### Initial Setup

```bash
# 1. Copy configurations
sudo cp fail2ban/filter.d/nginx-4xx.conf /etc/fail2ban/filter.d/
sudo cp fail2ban/filter.d/nginx-malicious-uri.conf /etc/fail2ban/filter.d/
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
|- Number of jail:      4
`- Jail list:   homeassistant-auth, nginx-4xx, nginx-malicious-uri, recidive
```

### Updates (After Config Changes)

```bash
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

See `CLAUDE.md` → Future Enhancements for migration plan.
