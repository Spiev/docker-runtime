#!/bin/bash
set -e  # Exit bei Fehler

IMAGE_TAG="nginx:stable"
COMPOSE_DIR="/home/stefan/docker/proxy"

# For logging details
echo "Script started at $(date --iso-8601=ns)"

echo "🔍 Prüfe neuestes nginx:stable arm64 Image..."

# Hole neuesten arm64-Digest
LATEST_DIGEST=$(docker manifest inspect $IMAGE_TAG 2>/dev/null | \
  jq -r '.manifests[] | select((.platform.architecture == "arm64" or .platform.architecture == "aarch64") and .platform.os == "linux") | .digest' | \
  head -n1)

if [ -z "$LATEST_DIGEST" ]; then
  echo "❌ Fehler: Konnte Digest nicht ermitteln"
  exit 1
fi

echo "📦 Neuester Digest: $LATEST_DIGEST"

# Prüfe ob schon aktuell
CURRENT_DIGEST=$(docker image inspect $IMAGE_TAG --format='{{index .RepoDigests 1}}' 2>/dev/null | cut -d'@' -f2)

if [ "$CURRENT_DIGEST" = "$LATEST_DIGEST" ]; then
  echo "✅ Image ist bereits aktuell!"
  exit 0
fi

echo "⬇️  Pulling neues Image by Digest..."
docker pull nginx@$LATEST_DIGEST

echo "🏷️  Tagge als nginx:stable..."
docker tag nginx@$LATEST_DIGEST $IMAGE_TAG

echo "🔄 Stoppe Container..."
cd $COMPOSE_DIR
docker compose down nginx

echo "🚀 Starte Container neu..."
docker compose up -d nginx

echo "🧹 Aufräumen alter Images..."
docker image prune -f

echo "✅ Update abgeschlossen!"

# Zeige neue Version
NEW_VERSION=$(docker exec proxy-nginx-1 nginx -v 2>&1 | awk -F'/' '{print $2}')
echo "📌 Neue Version: $NEW_VERSION"
