# Migration: home-assistant-matter-hub → Matterbridge

> **Erstellt:** 2026-01-27  
> **Grund:** `t0bst4r/home-assistant-matter-hub` ist seit Januar 2026 End of Maintenance  
> **Ziel:** `Luligu/matterbridge` mit `matterbridge-hass` Plugin

## Übersicht

| Aspekt | Alt (matter-hub) | Neu (matterbridge) |
|--------|------------------|-------------------|
| Image | `ghcr.io/t0bst4r/home-assistant-matter-hub:3.0.3` | `luligu/matterbridge:latest` |
| Matter Version | 1.3 | 1.4.2 |
| Konfiguration | `.env` Datei | Web-Frontend (Port 8283) |
| HA-Verbindung | Direkt (benötigt HA URL + Token) | WebSocket via Plugin |

---

## Wichtig: Plugin-System verstehen

> **Hinweis:** Das `matterbridge-hass` Plugin ist ein **Matterbridge Plugin**, KEIN Home Assistant Add-on!
>
> - Es wird im **Matterbridge Web-Frontend** installiert (Port 8283)
> - Es läuft **innerhalb** des Matterbridge Containers
> - Home Assistant bleibt **unverändert** – es stellt nur seine WebSocket API bereit
> - Funktioniert daher auch mit HA Docker (ohne Supervisor/Add-on Support)

```
┌─────────────────────────────────────────┐
│           Matterbridge Container         │
│  ┌─────────────────────────────────┐    │
│  │   matterbridge-hass Plugin      │    │  ← Plugin läuft IN Matterbridge
│  │   (wird über Web-UI installiert)│    │
│  └──────────────┬──────────────────┘    │
└─────────────────┼───────────────────────┘
                  │ WebSocket
                  ▼
┌─────────────────────────────────────────┐
│      Home Assistant Container            │  ← Dein bestehender HA Docker
│      (unverändert, keine Plugins nötig) │
└─────────────────────────────────────────┘
```

---

## Voraussetzungen

- [ ] Home Assistant Long-Lived Access Token erstellen
- [ ] Aktuelle Matter-Hub Konfiguration sichern (welche Entities sind exponiert?)
- [ ] Google Home App bereit zum Re-Pairing

---

## Phase 1: Vorbereitung

### 1.1 Home Assistant Token erstellen

1. Home Assistant öffnen: `http://<YOUR-HA-IP>:8123`
2. Profil (unten links) → **Security**
3. **Long-Lived Access Tokens** → "Create Token"
4. Name: `matterbridge`
5. Token sicher speichern (wird nur einmal angezeigt!)

### 1.2 Aktuelle Konfiguration dokumentieren

```bash
# Matter-Hub Konfiguration anschauen
cat ~/docker/homeassistant/.env

# Notiere dir:
# - Welche Domains/Entities sind exponiert?
# - Welche Filter sind aktiv?
```

### 1.3 Google Home: Altes Gerät entfernen

1. Google Home App öffnen
2. Matter-Hub Bridge finden
3. Gerät entfernen (wichtig vor Migration!)

---

## Phase 2: Matter-Hub stoppen

```bash
cd ~/docker/homeassistant

# Container stoppen (nicht löschen, falls Rollback nötig)
docker compose stop matter-hub

# Optional: Logs sichern
docker logs matter-hub > matter-hub-backup.log 2>&1
```

---

## Phase 3: Matterbridge installieren

### 3.1 Docker Compose anpassen

Ersetze in `docker-compose.yml` den `matter-hub` Service:

```yaml
  # ALT: matter-hub (auskommentiert für Rollback)
  # matter-hub:
  #   image: ghcr.io/t0bst4r/home-assistant-matter-hub:3.0.3
  #   container_name: matter-hub
  #   restart: unless-stopped
  #   network_mode: host
  #   env_file:
  #     - .env
  #   volumes:
  #     - $PWD/home-assistant-matter-hub:/data

  # NEU: Matterbridge
  matterbridge:
    image: luligu/matterbridge:latest
    container_name: matterbridge
    restart: unless-stopped
    network_mode: host
    volumes:
```

### 3.2 Verzeichnisse erstellen

```bash
cd ~/docker/homeassistant
mkdir -p matterbridge matterbridge-data
```

### 3.3 Matterbridge starten

```bash
docker compose up -d matterbridge

# Logs prüfen
docker logs -f matterbridge
```

---

## Phase 4: Matterbridge konfigurieren

### 4.1 Web-Frontend öffnen

- URL: `http://<YOUR-HA-IP>:8283`
- Beim ersten Start wird ein QR-Code angezeigt (noch nicht scannen!)

### 4.2 Home Assistant Plugin installieren

1. Im Frontend: **Plugins** → Suche nach `matterbridge-hass`
2. **Install** klicken
3. Warten bis Installation abgeschlossen

### 4.3 Plugin konfigurieren

1. **Plugins** → `matterbridge-hass` → **Config**
2. Einstellungen:

| Feld | Wert |
|------|------|
| **host** | `ws://<YOUR-HA-IP>:8123` |
| **token** | `<dein-long-lived-token>` |
| **filterByArea** | Optional: Areas auswählen |
| **filterByLabel** | Optional: Labels auswählen |
| **whiteList** | Entities die exponiert werden sollen |
| **blackList** | Entities die NICHT exponiert werden sollen |

> **Hinweis:** Wenn dein Home Assistant über HTTPS/SSL erreichbar ist (z. B. via Reverse Proxy oder öffentlicher URL), verwende im Feld **host** statt `ws://` unbedingt `wss://`, damit die WebSocket‑Verbindung funktioniert und verschlüsselt ist.

3. **Save** und **Restart Plugin**

### 4.4 Prüfen ob Entities geladen wurden

- Frontend: **Devices** Tab
- Alle gewünschten Entities sollten sichtbar sein

---

## Phase 5: Mit Google Home pairen

### 5.1 QR-Code scannen

1. Matterbridge Frontend: **Home** Tab
2. QR-Code wird angezeigt
3. Google Home App → **+** → **Gerät einrichten** → **Matter-fähiges Gerät**
4. QR-Code scannen

### 5.2 Pairing abschließen

- Google Home sollte die Bridge finden
- Alle Entities werden als Geräte angezeigt
- Räume zuweisen

---

## Phase 6: Aufräumen

### 6.1 Alten Matter-Hub Service entfernen

Nach erfolgreicher Migration (ca. 1 Woche testen):

```bash
cd ~/docker/homeassistant

# Alte Daten löschen
rm -rf home-assistant-matter-hub

# docker-compose.yml: Auskommentierten matter-hub Block entfernen
```

### 6.2 .env Datei bereinigen

Entferne matter-hub spezifische Variablen aus `.env`:
- `HOME_ASSISTANT_URL`
- `HOME_ASSISTANT_ACCESS_TOKEN`
- `HAMH_*` Variablen

---

## Rollback (falls nötig)

Falls Probleme auftreten:

```bash
cd ~/docker/homeassistant

# Matterbridge stoppen
docker compose stop matterbridge

# Matter-Hub wieder starten
docker compose start matter-hub

# Google Home: Neu pairen mit alter Bridge
```

---

## Bekannte Einschränkungen

### Apple Home (falls relevant)
- Robot Vacuum muss im "Server Mode" laufen
- RVC darf keine anderen Device-Types haben (Switches blacklisten)

### Google Home
- Thermostat: Fahrenheit/Celsius Bug (Google-seitig)
- Workaround: Auf iPhone pairen, dann funktioniert Android

---

## Nach der Migration

### Dokumentation aktualisieren

- [ ] `CLAUDE.md` aktualisieren (matter-hub → matterbridge)
- [ ] `docker-compose.yml` Kommentare anpassen
- [ ] Dependabot: Neues Image tracken lassen

### Monitoring

Matterbridge hat ein eigenes Frontend mit:
- Device Status
- Logs
- Plugin Management

URL: `http://<YOUR-HA-IP>:8283`

---

## Hilfreiche Links

- [Matterbridge GitHub](https://github.com/Luligu/matterbridge)
- [matterbridge-hass Plugin](https://github.com/Luligu/matterbridge-hass)
- [Matterbridge Discord](https://discord.gg/QX58CDe6hd)
- [Docker README](https://github.com/Luligu/matterbridge/blob/main/README-DOCKER.md)
