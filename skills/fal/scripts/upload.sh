#!/bin/bash

# fal.ai File Upload Script
# Usage: ./upload.sh --file /path/to/file
# Returns: CDN URL for the uploaded file

set -e

FAL_TOKEN_ENDPOINT="https://rest.alpha.fal.ai/storage/auth/token?storage_type=fal-cdn-v3"
FILE_PATH=""

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --file|-f) FILE_PATH="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: ./upload.sh --file /path/to/file" >&2
      echo "Outputs: CDN URL of uploaded file" >&2
      exit 0
      ;;
    *)
      if [ -z "$FILE_PATH" ] && [ -f "$1" ]; then FILE_PATH="$1"; fi
      shift
      ;;
  esac
done

if [ -z "$FAL_KEY" ]; then echo "Error: FAL_KEY not set" >&2; exit 1; fi
if [ -z "$FILE_PATH" ]; then echo "Error: --file required" >&2; exit 1; fi
if [ ! -f "$FILE_PATH" ]; then echo "Error: File not found: $FILE_PATH" >&2; exit 1; fi

FILENAME=$(basename "$FILE_PATH")
EXT=$(echo "${FILENAME##*.}" | tr '[:upper:]' '[:lower:]')

case "$EXT" in
  jpg|jpeg) CT="image/jpeg" ;; png) CT="image/png" ;; gif) CT="image/gif" ;;
  webp) CT="image/webp" ;; mp4) CT="video/mp4" ;; mov) CT="video/quicktime" ;;
  mp3) CT="audio/mpeg" ;; wav) CT="audio/wav" ;; *) CT="application/octet-stream" ;;
esac

echo "Uploading: $FILENAME" >&2

TOKEN_RESP=$(curl -s -X POST "$FAL_TOKEN_ENDPOINT" \
  -H "Authorization: Key $FAL_KEY" -H "Content-Type: application/json" -d '{}')

TOKEN=$(echo "$TOKEN_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
TOKEN_TYPE=$(echo "$TOKEN_RESP" | grep -o '"token_type":"[^"]*"' | cut -d'"' -f4)
BASE_URL=$(echo "$TOKEN_RESP" | grep -o '"base_url":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ] || [ -z "$BASE_URL" ]; then echo "Error: CDN token failed" >&2; exit 1; fi

UPLOAD_RESP=$(curl -s -X POST "${BASE_URL}/files/upload" \
  -H "Authorization: $TOKEN_TYPE $TOKEN" \
  -H "Content-Type: $CT" \
  -H "X-Fal-File-Name: $FILENAME" \
  --data-binary "@$FILE_PATH")

ACCESS_URL=$(echo "$UPLOAD_RESP" | grep -o '"access_url":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ACCESS_URL" ]; then echo "Error: Upload failed" >&2; exit 1; fi

echo "Uploaded: $ACCESS_URL" >&2
echo "$ACCESS_URL"
