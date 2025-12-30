#!/bin/bash
CONTAINER_NAME="proxy-nginx-1"
IMAGE_TAG="nginx:stable-alpine"

# For logging details
echo "Script started at $(date --iso-8601=ns)"

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

# Platform
PLATFORM=$(docker version --format '{{.Server.Arch}}')

# Digests
# Multi-platform images have multiple RepoDigests (manifest list + platform-specific)
# We need to check both against the remote digest
LOCAL_DIGEST_1=$(docker image inspect $IMAGE_TAG --format='{{index .RepoDigests 0}}' 2>/dev/null | cut -d'@' -f2)
LOCAL_DIGEST_2=$(docker image inspect $IMAGE_TAG --format='{{index .RepoDigests 1}}' 2>/dev/null | cut -d'@' -f2)

REMOTE_DIGEST=$(docker manifest inspect $IMAGE_TAG 2>/dev/null | \
  jq -r '.manifests[] | select((.platform.architecture == "arm64" or .platform.architecture == "aarch64") and .platform.os == "linux") | .digest' | \
  head -n1)

# Aktuelle Version
CURRENT_VERSION=$(docker exec "$CONTAINER_NAME" nginx -v 2>&1 | awk -F'/' '{print $2}')

# Timestamps
# Lokales Image: wann wurde es erstellt/gepullt
LOCAL_CREATED=$(docker image inspect $IMAGE_TAG --format='{{.Created}}' 2>/dev/null)
LOCAL_CREATED_TS=$(date -d "$LOCAL_CREATED" +%s 2>/dev/null || echo "0")
LOCAL_CREATED_HUMAN=$(date -d "$LOCAL_CREATED" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unbekannt")

# Ersetze im Script die REMOTE_CREATED Zeile mit:
# Hole Config des Remote-Images direkt
REMOTE_CONFIG=$(docker buildx imagetools inspect nginx@$REMOTE_DIGEST --format '{{json .}}' 2>/dev/null)
REMOTE_CREATED=$(echo "$REMOTE_CONFIG" | jq -r '.config.created' 2>/dev/null)

# Falls das auch nicht klappt, Alternative via Manifest-Inspektion:
if [ -z "$REMOTE_CREATED" ] || [ "$REMOTE_CREATED" = "null" ]; then
  # Fallback: Hole aus dem Platform-spezifischen Manifest
  REMOTE_CREATED=$(docker manifest inspect nginx@$REMOTE_DIGEST 2>/dev/null | \
    jq -r '.config.digest' | \
    xargs -I {} docker manifest inspect nginx@{} 2>/dev/null | \
    jq -r '.created' 2>/dev/null)
fi

REMOTE_CREATED_TS=$(date -d "$REMOTE_CREATED" +%s 2>/dev/null || echo "0")
REMOTE_CREATED_HUMAN=$(date -d "$REMOTE_CREATED" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unbekannt")


# Status
# Check both local digests against remote (one of them should match for multi-platform images)
if ([ "$LOCAL_DIGEST_1" = "$REMOTE_DIGEST" ] || [ "$LOCAL_DIGEST_2" = "$REMOTE_DIGEST" ]) && [ -n "$REMOTE_DIGEST" ]; then
  STATUS="Aktuell"
else
  STATUS="Update verfügbar"
fi

# For output: Use the first non-empty digest
LOCAL_DIGEST="${LOCAL_DIGEST_1:-$LOCAL_DIGEST_2}"

# Wie alt ist das lokale Image (in Tagen)
if [ "$LOCAL_CREATED_TS" != "0" ]; then
  NOW=$(date +%s)
  AGE_DAYS=$(( ($NOW - $LOCAL_CREATED_TS) / 86400 ))
else
  AGE_DAYS="unbekannt"
fi

JSON="{\"current\":\"$CURRENT_VERSION\",\"platform\":\"$PLATFORM\",\"local_digest\":\"${LOCAL_DIGEST:0:12}\",\"remote_digest\":\"${REMOTE_DIGEST:0:12}\",\"status\":\"$STATUS\",\"local_created\":\"$LOCAL_CREATED_HUMAN\",\"remote_created\":\"$REMOTE_CREATED_HUMAN\",\"image_age_days\":$AGE_DAYS}"

echo $JSON

# MQTT
mosquitto_pub -d -h localhost -p 1883 \
  -u "$MQTT_USER" -P "$MQTT_PASSWORD" \
  -t nginx/status \
  -m "$JSON"
