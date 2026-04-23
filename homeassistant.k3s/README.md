# Home Assistant

Home Assistant läuft aktuell noch als Docker-Container auf `raspberrypi` — die Migration zu k3s ist geplant (Agent-Node, `hostNetwork` + Zigbee-Dongle).

Dieser Ordner enthält HA-Konfiguration und Dashboards die zur k3s-Infrastruktur gehören — unabhängig davon ob HA selbst schon auf k3s läuft.

## Dashboards

| Datei | Inhalt |
|---|---|
| [dashboards/backup-k3s.yaml](dashboards/backup-k3s.yaml) | Homelab-Dashboard: Hardware, Backup Pi1, Backup k3s, Services |

Das Dashboard lebt im Code — Änderungen im Repo werden automatisch via Cron in HA übernommen.

### Einmalig: HA konfigurieren

**1. Lovelace-Eintrag in `configuration.yaml` ergänzen** (siehe `configuration.yaml.example`):

```yaml
lovelace:
  dashboards:
    homelab:
      mode: yaml
      filename: dashboards/homelab.yaml
      title: Homelab
      icon: mdi:home
      show_in_sidebar: true
```

**2. Deploy-Script einrichten:**

```bash
cd ~/docker/scripts
cp deploy-dashboard.sh.example deploy-dashboard.sh
chmod 700 deploy-dashboard.sh
```

**3. Cron einrichten** (`crontab -e`):

```
*/15 * * * * /home/stefan/docker/scripts/deploy-dashboard.sh >> /home/stefan/docker/logs/deploy-dashboard.log 2>&1
```

**4. Manuell einmalig ausführen:**

```bash
mkdir -p ~/docker/logs
~/docker/scripts/deploy-dashboard.sh
```

Danach erscheint "Homelab" in der HA-Sidebar. Sensoren erscheinen automatisch via MQTT Discovery nach dem ersten Backup-Lauf.
