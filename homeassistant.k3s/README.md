# Home Assistant

Home Assistant läuft aktuell noch als Docker-Container auf `raspberrypi` — die Migration zu k3s ist geplant (Agent-Node, `hostNetwork` + Zigbee-Dongle).

Dieser Ordner enthält HA-Konfiguration und Dashboards die zur k3s-Infrastruktur gehören — unabhängig davon ob HA selbst schon auf k3s läuft.

## Dashboards

| Datei | Inhalt |
|---|---|
| [dashboards/homelab.yaml](dashboards/homelab.yaml) | Homelab-Dashboard: Hardware, Backup, Netzwerk, Services |
| [dashboards/licht.yaml](dashboards/licht.yaml) | Licht-Dashboard: alle Lichter nach Raum, Tile-Karten mit Dimmer |

Die Dashboards leben im Code — Änderungen im Repo werden automatisch via Cron in HA übernommen. Das Deploy-Script kopiert **alle** `dashboards/*.yaml`; ein neues Dashboard-File wird also ohne Script-Anpassung übernommen.

### Einmalig: HA konfigurieren

**1. Lovelace-Eintrag in `configuration.yaml` ergänzen** (siehe `configuration.yaml.example`):

```yaml
lovelace:
  dashboards:
    homelab-dashboard:
      mode: yaml
      filename: dashboards/homelab.yaml
      title: "11 Homelab"
      icon: mdi:home
      show_in_sidebar: true
    licht-dashboard:
      mode: yaml
      filename: dashboards/licht.yaml
      title: "09 Licht"
      icon: mdi:lightbulb-group
      show_in_sidebar: true
```

> **Sidebar-Reihenfolge:** HA sortiert die Dashboards alphabetisch nach `title` (Ziffern vor Buchstaben; „Übersicht"/Einstellungen sind fest gepinnt). Das Zahlen-Präfix im Titel bestimmt also die Position. Alternativ ginge Drag&Drop unter Profil → „Seitenleiste bearbeiten" — das ist aber pro Benutzer gespeichert und nicht versioniert. Ein `title`-Wechsel wird erst nach **HA-Neustart** in der Sidebar sichtbar.

> **Hinweis:** Ein **neues** Dashboard in `lovelace.dashboards` wird erst nach einem **HA-Neustart** in der Sidebar registriert. Änderungen am Dashboard-*Inhalt* (bestehende YAML-Files) übernimmt der `reload_all` des Sync-Scripts dagegen ohne Neustart.

**2. Deploy-Script einrichten:**

```bash
cd ~/docker/scripts
cp deploy-dashboard.sh.example ha_dashboard_sync.sh
chmod 700 ha_dashboard_sync.sh
cp .ha.env.example .ha.env
chmod 600 .ha.env
# HA_TOKEN: Long-lived access token (HA → Profil → Sicherheit → unten)
# HA_URL:   http://localhost:8123
```

**3. Cron einrichten** (`crontab -e`):

```
*/15 * * * * /home/stefan/docker/scripts/ha_dashboard_sync.sh >> /home/stefan/docker/logs/ha_dashboard_sync.log 2>&1
```

**4. Manuell einmalig ausführen:**

```bash
mkdir -p ~/docker/logs
~/docker/scripts/ha_dashboard_sync.sh
```

Danach erscheint "Homelab" in der HA-Sidebar. Sensoren erscheinen automatisch via MQTT Discovery nach dem ersten Backup-Lauf.
