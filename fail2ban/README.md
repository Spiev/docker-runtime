# Fail2ban Configuration for Docker Homelab

This directory contains fail2ban configuration files for protecting Nginx-proxied Docker services.

## Architecture

**Deployment:** Host-based (not containerized)
**Why host-based?**
- ✅ Lower overhead (no Docker-in-Docker)
- ✅ Blocks traffic BEFORE it reaches Docker (DOCKER-USER iptables chain)
- ✅ No privileged container required
- ✅ Protects all Docker services simultaneously

## Protection Coverage

### 3 Layers of Defense

#### 1. Authentication Protection (`*-auth` jails)
- Monitors 401 Unauthorized responses on login endpoints
- **Endpoints:** `/api/auth`, `/api/token`, `/api/user`, `/login`, `/api/greader`
- **Threshold:** 5 failed attempts in 10 minutes
- **Action:** 1 hour ban

#### 2. Rate Limiting Abuse (`*-rate-limit` jails)
- Monitors 503 Service Unavailable (triggered by Nginx rate limiting)
- **Threshold:** 20 violations in 5 minutes
- **Action:** 30 minute ban

#### 3. Reconnaissance/Scanning (`*-scan` jails)
- Monitors 403/404 on suspicious paths (wp-admin, phpMyAdmin, .env, .git, etc.)
- **Threshold:** 10 suspicious requests in 10 minutes
- **Action:** 24 hour ban

### Recidive (Repeat Offender Protection)
- Monitors fail2ban's own log for repeat bans
- **Threshold:** 3 bans within 24 hours
- **Action:** 1 week ban

## File Structure

```
fail2ban/
├── filter.d/
│   ├── nginx-auth-failed.conf           # NEW: 401 on auth endpoints
│   ├── nginx-rate-limit-abuse.conf      # NEW: 503 rate limit violations
│   ├── nginx-forbidden-scan.conf        # NEW: 403/404 reconnaissance
│   └── nginx-immich-proxy.conf          # OLD: Generic 401/403/404 (deprecated)
│
├── jail.d/
│   ├── immich.local                     # UPDATED: 3 jails for Immich
│   ├── paperless.local                  # NEW: 3 jails for Paperless
│   ├── freshrss.local                   # NEW: 3 jails for FreshRSS
│   └── recidive.local                   # NEW: Repeat offender protection
│
└── jail.local                           # sshd jail disabled
```

## Deployment

### Initial Setup (First Time)

```bash
# 1. Copy all configurations
sudo cp fail2ban/filter.d/*.conf /etc/fail2ban/filter.d/
sudo cp fail2ban/jail.d/*.local /etc/fail2ban/jail.d/
sudo cp fail2ban/jail.local /etc/fail2ban/jail.local

# 2. Copy helper scripts to user bin
sudo cp fail2ban/fail2ban-status.sh /usr/local/bin/fail2ban-status
sudo cp fail2ban/fail2ban-motd.sh /usr/local/bin/fail2ban-motd
sudo chmod +x /usr/local/bin/fail2ban-status
sudo chmod +x /usr/local/bin/fail2ban-motd

# 3. Test configuration
sudo fail2ban-client -t

# 4. Restart fail2ban
sudo systemctl restart fail2ban

# 5. Verify jails are running
sudo fail2ban-client status

# 6. Test status script
sudo fail2ban-status
```

### Enable Login Banner (Optional)

To see fail2ban status automatically on SSH login:

```bash
# Add to your ~/.bashrc
echo "" >> ~/.bashrc
echo "# Fail2ban status on login" >> ~/.bashrc
echo "sudo /usr/local/bin/fail2ban-motd" >> ~/.bashrc

# Or add to /etc/profile.d/ for all users (requires sudo)
sudo cp fail2ban/fail2ban-motd.sh /etc/profile.d/fail2ban-motd.sh
sudo chmod +x /etc/profile.d/fail2ban-motd.sh
```

**Note:** The login banner only shows if there are banned IPs or failed attempts.

Expected output:
```
Status
|- Number of jail:      10
`- Jail list:   immich-auth, immich-rate-limit, immich-scan,
                paperless-auth, paperless-rate-limit, paperless-scan,
                freshrss-auth, freshrss-rate-limit, freshrss-scan,
                recidive
```

### Updates (After Modifying Configs)

```bash
# Copy modified files
sudo cp fail2ban/filter.d/*.conf /etc/fail2ban/filter.d/
sudo cp fail2ban/jail.d/*.local /etc/fail2ban/jail.d/

# Test config
sudo fail2ban-client -t

# Reload (preserves current bans)
sudo systemctl reload fail2ban
```

## Monitoring & Maintenance

### Quick Status Overview (Recommended) ⭐

```bash
# Compact overview of all jails
sudo fail2ban-status
```

**Example output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Fail2ban Status Overview
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

JAIL                      BANNED   FAILED  TOTAL BAN  TOTAL FAIL
─────────────────────────────────────────────────────────────────
✓  immich-auth                 0        0          2          15
⚠  immich-rate-limit           1        0          3          42
✓  immich-scan                 0        0          0           0
✓  paperless-auth              0        2          1           8
✓  paperless-rate-limit        0        0          0           0
✓  paperless-scan              0        0          0           0
✓  freshrss-auth               0        0          0           0
✓  freshrss-rate-limit         0        0          0           0
✓  freshrss-scan               0        0          1           5
✓  recidive                    0        0          0           0
─────────────────────────────────────────────────────────────────
TOTAL (10 jails)               1        2

⚠ 1 IP(s) currently banned

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Verbose mode (shows banned IPs and recent activity):**
```bash
sudo fail2ban-status --verbose
```

### Native fail2ban Commands

#### Check Active Jails
```bash
sudo fail2ban-client status
```

#### Check Specific Jail
```bash
sudo fail2ban-client status immich-auth
```

#### View Banned IPs
```bash
sudo fail2ban-client banned
```

#### Unban an IP
```bash
sudo fail2ban-client unban 192.0.2.123
```

### Test Filters Against Logs

```bash
# Test auth-failed filter
sudo fail2ban-regex /home/stefan/docker/proxy/nginx/logs/access.log \
  /etc/fail2ban/filter.d/nginx-auth-failed.conf

# Test rate-limit filter
sudo fail2ban-regex /home/stefan/docker/proxy/nginx/logs/access.log \
  /etc/fail2ban/filter.d/nginx-rate-limit-abuse.conf

# Test scanning filter
sudo fail2ban-regex /home/stefan/docker/proxy/nginx/logs/access.log \
  /etc/fail2ban/filter.d/nginx-forbidden-scan.conf
```

### Monitor Fail2ban Activity

```bash
# Live log monitoring
sudo tail -f /var/log/fail2ban.log

# Recent bans
sudo journalctl -u fail2ban -n 100

# Search for specific IP
sudo grep "192.0.2.123" /var/log/fail2ban.log
```

## Important Notes

### Log Path
- All jails monitor: `/home/stefan/docker/proxy/nginx/logs/access.log`
- This log is mounted from the Nginx Docker container
- Ensure the path is correct for your system

### Ignored IPs
All jails ignore RFC1918 private networks:
- `127.0.0.1/8` (localhost)
- `192.168.0.0/16` (private)
- `172.16.0.0/12` (private)
- `10.0.0.0/8` (private)

### iptables Chain
- All jails target: `DOCKER-USER` chain
- This chain is processed BEFORE Docker's routing
- Bans affect ALL Docker containers, not just Nginx

## Troubleshooting

### Jail Not Starting
```bash
# Check fail2ban log for errors
sudo journalctl -u fail2ban -n 50

# Test specific jail config
sudo fail2ban-client -d | grep "jail_name"
```

### No Bans Happening
```bash
# Test if filter matches log entries
sudo fail2ban-regex /home/stefan/docker/proxy/nginx/logs/access.log \
  /etc/fail2ban/filter.d/nginx-auth-failed.conf --print-all-matched

# Check if log file is readable
sudo ls -la /home/stefan/docker/proxy/nginx/logs/access.log
```

### Accidentally Banned Yourself
```bash
# Unban your IP
sudo fail2ban-client unban YOUR_IP

# Add your IP to ignoreip in jail config (emergency)
sudo nano /etc/fail2ban/jail.d/immich.local
# Add to ignoreip line: ignoreip = ... YOUR_IP
sudo systemctl reload fail2ban
```

## Migration Notes

### From Old Setup
The old `nginx-immich-proxy.conf` filter was too generic (matched all 401/403/404).

**New approach:**
- Separate filters for different attack types
- More specific regex patterns
- Better false positive prevention

**Old jail:** `[immich]` (single jail)
**New jails:** `[immich-auth]`, `[immich-rate-limit]`, `[immich-scan]` (3 specialized jails)

### Backwards Compatibility
The old filter still exists but is deprecated. The old `[immich]` jail has been replaced with `[immich-auth]`.

## Security Considerations

### Ban Duration Philosophy
- **Auth failures:** 1 hour (legitimate users locked out briefly)
- **Rate limit abuse:** 30 minutes (might be bots or API clients)
- **Scanning:** 24 hours (clear malicious intent)
- **Recidive:** 1 week (persistent attackers)

### Threshold Tuning
Current thresholds are conservative. Adjust based on your threat model:

**More strict (aggressive):**
```
maxretry = 3
findtime = 300  # 5 minutes
```

**More lenient (relaxed):**
```
maxretry = 10
findtime = 1800  # 30 minutes
```

### Performance Impact
- Minimal CPU overhead (Python-based log parsing)
- Memory: ~50MB for fail2ban process
- Network: No impact (iptables rules are kernel-level)

## References

- fail2ban documentation: https://www.fail2ban.org/
- Nginx log format: http://nginx.org/en/docs/http/ngx_http_log_module.html
- Docker iptables integration: https://docs.docker.com/network/iptables/
