# Teslamate Setup

Tesla-Datenlogger mit Grafana-Dashboards und Home Assistant Integration.

## Quick Start

### 1. Konfiguration erstellen

```bash
cd teslamate
cp .env.example .env
chmod 600 .env
```

Editiere `.env` und setze:
- `ENCRYPTION_KEY`: Generieren mit `openssl rand -base64 32`
- `TM_DB_PASS`: Sicheres Datenbankpasswort
- `MQTT_USERNAME`/`MQTT_PASSWORD`: Deine Mosquitto-Credentials
- `GRAFANA_PASSWORD`: Sicheres Grafana-Passwort

### 2. Grafana-Verzeichnis vorbereiten

Grafana läuft als User 472, daher müssen die Berechtigungen stimmen:

```bash
mkdir -p grafana
sudo chown -R 472:472 grafana
```

### 3. Container starten

```bash
docker compose up -d
```

### 4. Tesla Account verbinden

1. Öffne http://raspberrypi:4000 (oder deine IP)
2. Folge dem Login-Prozess
3. **Wichtig für Model 3 Highland**: Virtual Key hinzufügen!

### Virtual Key (Pflicht für 2021+ Fahrzeuge)

Neuere Tesla-Fahrzeuge erfordern einen Virtual Key:

1. Gehe zu https://tesla.com/_ak/teslamate.example.com
2. Ersetze `teslamate.example.com` mit deiner Domain (oder nutze localhost-Workaround)
3. Bestätige in der Tesla-App auf deinem Handy
4. Setze in `.env`: `VIRTUAL_KEY=true`

Siehe: https://docs.teslamate.org/docs/faq#why-do-i-need-to-add-a-virtual-key

## Zugriff

| Service | URL | Beschreibung |
|---------|-----|--------------|
| Teslamate | http://raspberrypi:4000 | Hauptanwendung, Tesla Login |
| Grafana | http://raspberrypi:3000 | Dashboards (vorkonfiguriert!) |

## Home Assistant Integration

1. Kopiere relevante Teile aus `homeassistant-example.yaml` in deine HA-Config
2. Starte Home Assistant neu
3. Neue Sensoren erscheinen automatisch via MQTT

### Wichtige Sensoren

| Sensor | Beschreibung |
|--------|--------------|
| `sensor.tesla_battery_level` | Aktueller Ladestand (%) |
| `sensor.tesla_charge_energy_added` | Energie der aktuellen Ladung (kWh) |
| `sensor.tesla_charging_cost_current` | Kosten der aktuellen Ladung (EUR) |
| `sensor.tesla_energy_monthly` | Monatlich geladene Energie (kWh) |

### Monatliche Kosten berechnen

Der `utility_meter` in der Beispiel-Config trackt die monatlich geladene Energie.
Die Kosten bei 0,45 EUR/kWh:

```yaml
template:
  - sensor:
      - name: "Tesla Ladekosten Monat"
        unit_of_measurement: "EUR"
        state: "{{ (states('sensor.tesla_energy_monthly') | float(0) * 0.45) | round(2) }}"
```

## Grafana Dashboards

Teslamate liefert vorkonfigurierte Dashboards:

- **Charges**: Alle Ladevorgänge mit Details
- **Charging Stats**: Statistiken über Zeit
- **Drives**: Fahrten mit Verbrauch
- **Efficiency**: Verbrauchsanalyse
- **Locations**: Häufig besuchte Orte
- **Overview**: Gesamtübersicht

Login: `admin` / (dein GRAFANA_PASSWORD aus .env)

## Backup

Die PostgreSQL-Datenbank enthält alle historischen Daten.
Backup erstellen:

```bash
docker exec teslamate-db pg_dumpall -U teslamate | gzip > teslamate_backup_$(date +%Y%m%d).sql.gz
```

## Troubleshooting

### Tesla Login funktioniert nicht
- Prüfe ob Virtual Key hinzugefügt wurde
- Tesla API kann temporär überlastet sein

### Keine Daten in Home Assistant
- Prüfe MQTT-Verbindung: `docker logs teslamate | grep -i mqtt`
- Prüfe Mosquitto-Logs: `docker logs mosquitto`

### Grafana zeigt keine Daten
- Warte einige Minuten nach dem ersten Start
- Prüfe Datenbankverbindung in Grafana → Data Sources

### Grafana startet nicht (Permission denied)
Fehlermeldung: `GF_PATHS_DATA is not writable` oder `mkdir: can't create directory '/var/lib/grafana/plugins': Permission denied`

Fix:
```bash
sudo chown -R 472:472 ~/docker/teslamate/grafana
docker compose restart grafana
```
