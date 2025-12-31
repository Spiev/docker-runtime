# Docker Homelab Infrastructure

A production-ready Docker Compose setup for self-hosted services on Raspberry Pi or similar home servers. This repository contains configurations for various services including reverse proxy, home automation, photo management, document management, and more.

## 🌟 Features

- **Production-tested** configurations for Raspberry Pi
- **Security-hardened** with fail2ban, rate limiting, and SSL
- **MQTT-based monitoring** integration with Home Assistant
- **Automated backups** with Restic
- **Template-based setup** - easy to customize for your environment

## 📦 Included Services

### Core Infrastructure
- **Nginx Reverse Proxy** - SSL termination with Let's Encrypt (certbot)
- **Pi-hole** - Network-wide ad blocking with DNS and IPv6 support
- **Fail2ban** - Intrusion prevention with custom filters

### Home Automation
- **Home Assistant** - Home automation hub
- **Mosquitto** - MQTT broker for IoT devices
- **Matter Hub** - Matter protocol bridge
- **Music Assistant** - Music aggregation service

### Media & Documents
- **Immich** - Photo and video management with ML features
- **Paperless-ngx** - Document management with OCR
- **FreshRSS** - RSS feed reader

### Monitoring & Automation
- **Backup Scripts** - Automated Restic backups with MQTT status reporting
- **Update Monitors** - Track Docker image and system updates via MQTT
- **Health Checks** - Nginx and system status monitoring

## 🚀 Quick Start

### Prerequisites

- Raspberry Pi 4/5 or similar ARM64 device (or adapt for x86_64)
- Docker and Docker Compose installed
- Domain names configured (for SSL certificates)
- Basic understanding of Docker and networking

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Spiev/docker-runtime.git
   cd docker-runtime
   ```

2. **Configure environment files:**
   ```bash
   # Each service directory contains .env.example files
   cd immich
   cp .env.example .env
   # Edit .env with your settings

   # Repeat for other services: proxy, paperless, etc.
   ```

3. **Setup monitoring scripts:**
   ```bash
   cd scripts

   # MQTT credentials (for monitoring)
   cp .mqtt_credentials.example .mqtt_credentials
   chmod 600 .mqtt_credentials
   # Edit with your MQTT broker credentials

   # Restic backup encryption
   cp .restic.env.example .restic.env
   chmod 600 .restic.env
   # Edit with your backup encryption password

   # Production scripts (adjust paths for your setup)
   cp backup-to-hdd.sh.example backup-to-hdd.sh
   cp nginx_update.sh.example nginx_update.sh
   cp check_raspi_update.sh.example check_raspi_update.sh

   # Make scripts executable
   chmod +x *.sh
   ```

4. **Start services:**
   ```bash
   # Start individual services
   cd proxy
   docker compose up -d

   # Or start all services (adjust as needed)
   ```

## 📂 Repository Structure

```
├── proxy/              # Nginx reverse proxy + Let's Encrypt
├── pihole/             # DNS-based ad blocker
├── homeassistant/      # Home automation stack
├── immich/             # Photo management
├── paperless/          # Document management
├── freshrss/           # RSS feed reader
├── fail2ban/           # Intrusion prevention configs
└── scripts/            # Monitoring and backup automation
    ├── *.example       # Template scripts (tracked in git)
    └── *.sh            # Production scripts (not in git, copy from .example)
```

## 🔒 Security Features

### SSL/TLS
- Automatic Let's Encrypt certificate management
- Multi-domain support with SANs
- Auto-renewal every 24 hours

### Hardening
- Nginx security headers (HSTS, CSP, X-Frame-Options, etc.)
- Rate limiting on authentication endpoints
- Connection limits per IP
- Service-specific timeouts and upload limits

### Fail2ban Protection
- Custom filters for Nginx auth failures, rate limiting, and scanning
- Per-service jails (Immich, Paperless, FreshRSS, Home Assistant)
- Recidive jail for repeat offenders
- DOCKER-USER iptables chain integration

### Credential Management
- All credentials in `.env` files (excluded from git)
- Template files (`.env.example`) for easy setup
- File permissions enforced (600 for credential files)
- No hardcoded secrets in scripts

## 📊 Monitoring

### MQTT Integration
All monitoring scripts send status updates to Home Assistant via MQTT:

- **Backup Status** - Real-time backup progress and statistics
- **Nginx Updates** - Docker image update notifications
- **System Updates** - Raspberry Pi package and firmware status

### Home Assistant Sensors

Scripts automatically create MQTT Discovery sensors:
- `sensor.restic_backup_status` - Backup state and metrics
- `sensor.nginx_docker_status` - Nginx update status
- `sensor.rpi_updates` - System update status

Example automation:
```yaml
automation:
  - alias: "Backup Failed Alert"
    trigger:
      - platform: state
        entity_id: sensor.restic_backup_status
        to: "failed"
    action:
      - service: notify.mobile_app
        data:
          title: "Backup Failed!"
          message: "Check backup logs immediately"
```

## 💾 Backup Strategy

### Restic Backups
- **Immich**: Backs up photo library including auto-exported database dumps
- **Paperless**: Exports PostgreSQL database, then backs up all documents
- **Home Assistant**: Backs up configuration, automations, dashboards, and custom components
- **Storage**: External HDD with encrypted Restic repository
- **Automation**: Cron-scheduled with MQTT status reporting

### Setup Backup Automation
```bash
# Add to crontab
crontab -e

# Daily backup at 2 AM with logging
0 2 * * * /path/to/scripts/backup-to-hdd.sh >> /path/to/logs/backup.log 2>&1
```

## 🔧 Common Operations

### SSL Certificate Management
```bash
cd proxy

# Force certificate renewal
docker compose run --rm certbot renew --force-renewal

# Check certificate status
docker exec proxy-nginx-1 ls -la /etc/letsencrypt/live/
```

### Service Updates
```bash
# Update specific service
cd immich
docker compose pull
docker compose up -d

# Automated Nginx updates
./scripts/nginx_update.sh
```

### Fail2ban Management
```bash
# Check jail status
sudo fail2ban-client status

# Unban IP
sudo fail2ban-client unban <IP_ADDRESS>

# View banned IPs
sudo fail2ban-client banned
```

## 🛠️ Customization

### Adapting for Your Environment

1. **Domain Configuration:**
   - Update `proxy/.env` with your domains
   - Modify `proxy/nginx/default.conf.template` for your services

2. **Script Paths:**
   - `scripts/nginx_update.sh`: Set `COMPOSE_DIR` to your proxy path
   - `scripts/backup-to-hdd.sh`: Set `DOCKER_BASE` to your Docker directory

3. **Hardware Dependencies:**
   - Home Assistant: Requires Zigbee USB dongle (`/dev/ttyACM0`)
   - Pi-hole: Requires DNS ports (53), may conflict with systemd-resolved

## 🤝 Contributing

This is a personal homelab setup, but feel free to:
- Open issues for questions or suggestions
- Fork and adapt for your own use
- Share improvements via pull requests

## 📝 License

This project is provided as-is for educational and personal use. Adapt as needed for your homelab.

## ⚠️ Important Notes

- **Security**: Review all configurations before exposing to the internet
- **Backups**: Test restore procedures regularly
- **Updates**: Keep Docker images and system packages up to date
- **Monitoring**: Set up alerts for critical services

## 🔗 Related Resources

- [Docker Documentation](https://docs.docker.com/)
- [Home Assistant](https://www.home-assistant.io/)
- [Immich](https://immich.app/)
- [Paperless-ngx](https://docs.paperless-ngx.com/)
- [Restic Backup](https://restic.net/)

---

**Built with ❤️ for the self-hosting community**
