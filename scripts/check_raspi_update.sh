#!/bin/bash

# MQTT Broker Details
MQTT_HOST="localhost" # Wenn auf dem gleichen Pi, könnte es 127.0.0.1 sein, aber du nutzt einen Container
MQTT_PORT="1883"
MQTT_TOPIC="homeassistant/sensor/rpi_updates/config"
STATE_TOPIC="rpi/update_status/state"
DEVICE_ID="rpi_homeassistant_host"
DEVICE_NAME="RPi Host System"

# Load MQTT credentials from secure file
SCRIPT_DIR="$(dirname "$0")"
CREDENTIALS_FILE="$SCRIPT_DIR/.mqtt_credentials"

if [ -f "$CREDENTIALS_FILE" ]; then
    source "$CREDENTIALS_FILE"
else
    echo "ERROR: MQTT credentials file not found at $CREDENTIALS_FILE" >&2
    echo "Please create it from .mqtt_credentials.example" >&2
    exit 1
fi

# 1. System-Updates zählen
UPDATES=$(sudo /usr/bin/apt update 2>/dev/null | /usr/bin/grep "can be upgraded" | /usr/bin/awk '{print $1}')
if [ -z "$UPDATES" ]; then
    UPDATES=0
fi

# 2. EEPROM Status prüfen
EEPROM_STATUS=$(sudo /usr/bin/rpi-eeprom-update | /usr/bin/grep "BOOTLOADER:" | /usr/bin/awk '{print $2,$3,$4}')
# Der Status ist entweder 'up' oder '***' bei required

# 3. Payload erstellen (ohne Discovery, nur als State)
PAYLOAD='{ "system_updates": '$UPDATES', "eeprom_status": "'$EEPROM_STATUS'" }'

echo $PAYLOAD

# 4. Über MQTT veröffentlichen
/usr/bin/mosquitto_pub -d -h $MQTT_HOST -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASSWORD" -t $STATE_TOPIC -m "$PAYLOAD"
