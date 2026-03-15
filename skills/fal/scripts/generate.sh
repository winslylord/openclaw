#!/bin/bash

# fal.ai Generation Script with Queue Support
# Usage: ./generate.sh --prompt "..." [--model MODEL] [options]
# Returns: JSON with generated media URLs
#
# Queue Mode (default): Submits to queue, polls for completion
# Async Mode: Returns request_id immediately
# Sync Mode: Direct request (not recommended for long tasks)

set -e

FAL_QUEUE_ENDPOINT="https://queue.fal.run"
FAL_SYNC_ENDPOINT="https://fal.run"
FAL_TOKEN_ENDPOINT="https://rest.alpha.fal.ai/storage/auth/token?storage_type=fal-cdn-v3"

# Default values
MODEL="fal-ai/flux/schnell"
PROMPT=""
IMAGE_URL=""
IMAGE_FILE=""
IMAGE_SIZE="landscape_4_3"
NUM_IMAGES=1
MODE="queue" # queue (default), async, sync
REQUEST_ID=""
ACTION="generate" # generate, status, result, cancel
POLL_INTERVAL=2
MAX_POLL_TIME=600
LIFECYCLE=""
SHOW_LOGS=false
OUTPUT_FILE=""

# Check for --add-fal-key first
for arg in "$@"; do
  if [ "$arg" = "--add-fal-key" ]; then
    shift
    KEY_VALUE=""
    if [[ -n "$1" && ! "$1" =~ ^-- ]]; then
      KEY_VALUE="$1"
    fi
    if [ -z "$KEY_VALUE" ]; then
      echo "Enter your fal.ai API key:" >&2
      read -r KEY_VALUE
    fi
    if [ -n "$KEY_VALUE" ]; then
      grep -v "^FAL_KEY=" .env > .env.tmp 2>/dev/null || true
      mv .env.tmp .env 2>/dev/null || true
      echo "FAL_KEY=$KEY_VALUE" >> .env
      echo "FAL_KEY saved to .env" >&2
    fi
    exit 0
  fi
done

# Load .env: check script's own directory first, then CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
  source "$SCRIPT_DIR/.env" 2>/dev/null || true
elif [ -f ".env" ]; then
  source .env 2>/dev/null || true
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --prompt|-p)
      PROMPT="$2"
      shift 2
      ;;
    --model|-m)
      MODEL="$2"
      shift 2
      ;;
    --image-url)
      IMAGE_URL="$2"
      shift 2
      ;;
    --file|--image)
      IMAGE_FILE="$2"
      shift 2
      ;;
    --size)
      case $2 in
        square) IMAGE_SIZE="square" ;;
        portrait) IMAGE_SIZE="portrait_4_3" ;;
        landscape) IMAGE_SIZE="landscape_4_3" ;;
        *) IMAGE_SIZE="$2" ;;
      esac
      shift 2
      ;;
    --num-images)
      NUM_IMAGES="$2"
      shift 2
      ;;
    --async)
      MODE="async"
      shift
      ;;
    --sync)
      MODE="sync"
      shift
      ;;
    --logs)
      SHOW_LOGS=true
      shift
      ;;
    --status)
      ACTION="status"
      REQUEST_ID="$2"
      shift 2
      ;;
    --result)
      ACTION="result"
      REQUEST_ID="$2"
      shift 2
      ;;
    --cancel)
      ACTION="cancel"
      REQUEST_ID="$2"
      shift 2
      ;;
    --filename|--output|-f)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --poll-interval)
      POLL_INTERVAL="$2"
      shift 2
      ;;
    --timeout)
      MAX_POLL_TIME="$2"
      shift 2
      ;;
    --lifecycle)
      LIFECYCLE="$2"
      shift 2
      ;;
    --schema)
      SCHEMA_MODEL="${2:-$MODEL}"
      ENCODED=$(echo "$SCHEMA_MODEL" | sed 's/\//%2F/g')
      echo "Fetching schema for $SCHEMA_MODEL..." >&2
      curl -s "https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=$ENCODED"
      exit 0
      ;;
    --help|-h)
      echo "fal.ai Generation Script (Queue-based)" >&2
      echo "" >&2
      echo "Usage: ./generate.sh --prompt \"...\" [options]" >&2
      echo "" >&2
      echo "Generation Options:" >&2
      echo "  --prompt, -p    Text description (required)" >&2
      echo "  --model, -m     Model ID (default: fal-ai/flux/schnell)" >&2
      echo "  --image-url     Input image URL for I2V models" >&2
      echo "  --file, --image Local file (auto-uploads to fal CDN)" >&2
      echo "  --size          square, portrait, landscape" >&2
      echo "  --num-images    Number of images (default: 1)" >&2
      echo "  --filename, -f  Download result to local file (outputs MEDIA: line)" >&2
      echo "" >&2
      echo "Mode Options:" >&2
      echo "  (default)       Queue mode - submit and poll" >&2
      echo "  --async         Return request_id immediately" >&2
      echo "  --sync          Synchronous (not recommended for video)" >&2
      echo "  --logs          Show generation logs while polling" >&2
      echo "" >&2
      echo "Queue Operations:" >&2
      echo "  --status ID     Check status of a queued request" >&2
      echo "  --result ID     Get result of a completed request" >&2
      echo "  --cancel ID     Cancel a queued request" >&2
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# Validate FAL_KEY
if [ -z "$FAL_KEY" ]; then
  echo "Error: FAL_KEY not set" >&2
  echo "Run: export FAL_KEY=your_key_here" >&2
  exit 1
fi

# Handle local file upload
if [ -n "$IMAGE_FILE" ]; then
  if [ ! -f "$IMAGE_FILE" ]; then
    echo "Error: File not found: $IMAGE_FILE" >&2
    exit 1
  fi

  FILENAME=$(basename "$IMAGE_FILE")
  EXTENSION="${FILENAME##*.}"
  EXTENSION_LOWER=$(echo "$EXTENSION" | tr '[:upper:]' '[:lower:]')

  case "$EXTENSION_LOWER" in
    jpg|jpeg) CONTENT_TYPE="image/jpeg" ;;
    png) CONTENT_TYPE="image/png" ;;
    gif) CONTENT_TYPE="image/gif" ;;
    webp) CONTENT_TYPE="image/webp" ;;
    mp4) CONTENT_TYPE="video/mp4" ;;
    mov) CONTENT_TYPE="video/quicktime" ;;
    *) CONTENT_TYPE="application/octet-stream" ;;
  esac

  echo "Uploading $FILENAME..." >&2

  TOKEN_RESPONSE=$(curl -s -X POST "$FAL_TOKEN_ENDPOINT" \
    -H "Authorization: Key $FAL_KEY" \
    -H "Content-Type: application/json" \
    -d '{}')

  CDN_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  CDN_TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | grep -o '"token_type":"[^"]*"' | cut -d'"' -f4)
  CDN_BASE_URL=$(echo "$TOKEN_RESPONSE" | grep -o '"base_url":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$CDN_TOKEN" ] || [ -z "$CDN_BASE_URL" ]; then
    echo "Error: Failed to get CDN token" >&2
    exit 1
  fi

  UPLOAD_RESPONSE=$(curl -s -X POST "${CDN_BASE_URL}/files/upload" \
    -H "Authorization: $CDN_TOKEN_TYPE $CDN_TOKEN" \
    -H "Content-Type: $CONTENT_TYPE" \
    -H "X-Fal-File-Name: $FILENAME" \
    --data-binary "@$IMAGE_FILE")

  IMAGE_URL=$(echo "$UPLOAD_RESPONSE" | grep -o '"access_url":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$IMAGE_URL" ]; then
    echo "Error: Failed to upload file" >&2
    exit 1
  fi

  echo "Uploaded: $IMAGE_URL" >&2
fi

# Build headers
HEADERS=(-H "Authorization: Key $FAL_KEY" -H "Content-Type: application/json")

if [ -n "$LIFECYCLE" ]; then
  HEADERS+=(-H "X-Fal-Object-Lifecycle-Preference: {\"expiration_duration_seconds\": $LIFECYCLE}")
fi

# Handle queue operations
case $ACTION in
  status)
    if [ -z "$REQUEST_ID" ]; then echo "Error: Request ID required" >&2; exit 1; fi
    LOGS_PARAM=""
    if [ "$SHOW_LOGS" = true ]; then LOGS_PARAM="?logs=1"; fi
    echo "Checking status for $REQUEST_ID..." >&2
    RESPONSE=$(curl -s -X GET "$FAL_QUEUE_ENDPOINT/$MODEL/requests/$REQUEST_ID/status$LOGS_PARAM" "${HEADERS[@]}")
    STATUS=$(echo "$RESPONSE" | grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//')
    echo "Status: $STATUS" >&2
    echo "$RESPONSE"
    exit 0
    ;;
  result)
    if [ -z "$REQUEST_ID" ]; then echo "Error: Request ID required" >&2; exit 1; fi
    echo "Getting result for $REQUEST_ID..." >&2
    RESPONSE=$(curl -s -X GET "$FAL_QUEUE_ENDPOINT/$MODEL/requests/$REQUEST_ID" "${HEADERS[@]}")
    echo "$RESPONSE"
    exit 0
    ;;
  cancel)
    if [ -z "$REQUEST_ID" ]; then echo "Error: Request ID required" >&2; exit 1; fi
    echo "Cancelling $REQUEST_ID..." >&2
    RESPONSE=$(curl -s -X PUT "$FAL_QUEUE_ENDPOINT/$MODEL/requests/$REQUEST_ID/cancel" "${HEADERS[@]}")
    echo "$RESPONSE"
    exit 0
    ;;
esac

# Generate requires prompt
if [ -z "$PROMPT" ]; then
  echo "Error: --prompt is required" >&2
  exit 1
fi

# Build payload using a heredoc to avoid quoting issues with special characters
if [[ "$MODEL" == *"image-to-video"* ]] || [[ "$MODEL" == *"i2v"* ]]; then
  if [ -z "$IMAGE_URL" ]; then
    echo "Error: --image-url required for image-to-video" >&2
    exit 1
  fi
  PAYLOAD=$(cat <<EOJSON
{"prompt": $(printf '%s' "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$PROMPT"), "image_url": "$IMAGE_URL"}
EOJSON
  )
else
  ESCAPED_PROMPT=$(printf '%s' "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)
  if [ -z "$ESCAPED_PROMPT" ]; then
    ESCAPED_PROMPT=$(printf '%s' "$PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g')
    ESCAPED_PROMPT="\"$ESCAPED_PROMPT\""
  fi
  PAYLOAD="{\"prompt\":$ESCAPED_PROMPT,\"image_size\":\"$IMAGE_SIZE\",\"num_images\":$NUM_IMAGES}"
fi

# Sync mode
if [ "$MODE" = "sync" ]; then
  echo "Generating (sync)..." >&2
  RESPONSE=$(curl -s -X POST "$FAL_SYNC_ENDPOINT/$MODEL" "${HEADERS[@]}" -d "$PAYLOAD")
  echo "$RESPONSE"
  exit 0
fi

# Queue mode
echo "Submitting to queue: $MODEL..." >&2

SUBMIT_RESPONSE=$(curl -s -X POST "$FAL_QUEUE_ENDPOINT/$MODEL" "${HEADERS[@]}" -d "$PAYLOAD")

REQUEST_ID=$(echo "$SUBMIT_RESPONSE" | grep -oE '"request_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//')
STATUS_URL=$(echo "$SUBMIT_RESPONSE" | grep -oE '"status_url"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//')
RESPONSE_URL=$(echo "$SUBMIT_RESPONSE" | grep -oE '"response_url"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//')

if [ -z "$REQUEST_ID" ]; then
  echo "Error: Failed to submit" >&2
  echo "$SUBMIT_RESPONSE" >&2
  exit 1
fi

echo "Request ID: $REQUEST_ID" >&2

# Async mode
if [ "$MODE" = "async" ]; then
  echo "Request submitted. Check with:" >&2
  echo "  Status: ./generate.sh --status \"$REQUEST_ID\" --model \"$MODEL\"" >&2
  echo "  Result: ./generate.sh --result \"$REQUEST_ID\" --model \"$MODEL\"" >&2
  echo "$SUBMIT_RESPONSE"
  exit 0
fi

# Poll until complete
echo "Waiting for completion..." >&2

ELAPSED=0
LAST_STATUS=""

while [ $ELAPSED -lt $MAX_POLL_TIME ]; do
  sleep $POLL_INTERVAL
  ELAPSED=$((ELAPSED + POLL_INTERVAL))

  LOGS_PARAM=""
  if [ "$SHOW_LOGS" = true ]; then LOGS_PARAM="?logs=1"; fi

  STATUS_RESPONSE=$(curl -s -X GET "${STATUS_URL}${LOGS_PARAM}" "${HEADERS[@]}")
  STATUS=$(echo "$STATUS_RESPONSE" | grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//')

  if [ "$STATUS" != "$LAST_STATUS" ]; then
    case $STATUS in
      IN_QUEUE)
        POSITION=$(echo "$STATUS_RESPONSE" | grep -o '"queue_position":[0-9]*' | cut -d':' -f2)
        echo "Status: IN_QUEUE (position: ${POSITION:-?})" >&2
        ;;
      IN_PROGRESS) echo "Status: IN_PROGRESS" >&2 ;;
      COMPLETED) echo "Status: COMPLETED" >&2 ;;
      *) echo "Status: $STATUS" >&2 ;;
    esac
    LAST_STATUS="$STATUS"
  fi

  if [ "$SHOW_LOGS" = true ]; then
    echo "$STATUS_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 | while read -r log; do
      echo "  > $log" >&2
    done
  fi

  if [ "$STATUS" = "COMPLETED" ]; then break; fi
  if [ "$STATUS" = "FAILED" ]; then
    echo "Error: Generation failed" >&2
    echo "$STATUS_RESPONSE"
    exit 1
  fi
done

if [ "$STATUS" != "COMPLETED" ]; then
  echo "Error: Timeout after ${MAX_POLL_TIME}s" >&2
  echo "Request ID: $REQUEST_ID" >&2
  exit 1
fi

# Fetch result
echo "Fetching result..." >&2
RESULT=$(curl -s -X GET "$RESPONSE_URL" "${HEADERS[@]}")

echo "" >&2
echo "Generation complete!" >&2

MEDIA_URL=""
MEDIA_KIND=""
if echo "$RESULT" | grep -q '"video"'; then
  MEDIA_URL=$(echo "$RESULT" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
  MEDIA_KIND="video"
  echo "Video URL: $MEDIA_URL" >&2
elif echo "$RESULT" | grep -q '"images"'; then
  MEDIA_URL=$(echo "$RESULT" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
  MEDIA_KIND="image"
  echo "Image URL: $MEDIA_URL" >&2
fi

# Convert Windows paths (C:\foo or C:/foo) to Unix paths for WSL/Git Bash
win_to_unix_path() {
  local p="$1"
  if [[ "$p" =~ ^([A-Za-z]):[/\\] ]]; then
    local drive="${BASH_REMATCH[1]}"
    local drive_lower=$(echo "$drive" | tr '[:upper:]' '[:lower:]')
    local rest="${p:3}"
    rest=$(echo "$rest" | tr '\\' '/')
    if [ -d "/mnt/$drive_lower" ]; then
      echo "/mnt/$drive_lower/$rest"
    else
      echo "/$drive_lower/$rest"
    fi
  else
    echo "$p"
  fi
}

# Convert Unix/WSL paths back to Windows format for MEDIA: output
unix_to_win_path() {
  local p="$1"
  if [[ "$p" =~ ^/mnt/([a-z])/(.*) ]]; then
    local drive="${BASH_REMATCH[1]}"
    local drive_upper=$(echo "$drive" | tr '[:lower:]' '[:upper:]')
    echo "${drive_upper}:/${BASH_REMATCH[2]}"
  elif [[ "$p" =~ ^/([a-z])/(.*) ]]; then
    local drive="${BASH_REMATCH[1]}"
    local drive_upper=$(echo "$drive" | tr '[:lower:]' '[:upper:]')
    echo "${drive_upper}:/${BASH_REMATCH[2]}"
  else
    echo "$p"
  fi
}

# Download to local file if --filename was provided
if [ -n "$OUTPUT_FILE" ] && [ -n "$MEDIA_URL" ]; then
  ORIGINAL_OUTPUT="$OUTPUT_FILE"
  OUTPUT_FILE=$(win_to_unix_path "$OUTPUT_FILE")
  OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
  mkdir -p "$OUTPUT_DIR" 2>/dev/null || true

  echo "Downloading $MEDIA_KIND to $OUTPUT_FILE..." >&2
  # fal.media CDN often works better without HTTP proxy; try noproxy first
  HTTP_CODE=$(curl -s -w '%{http_code}' --noproxy '*' -o "$OUTPUT_FILE" \
    --connect-timeout 10 --max-time 120 "$MEDIA_URL" 2>/dev/null)

  if [ "$HTTP_CODE" != "200" ] || [ ! -s "$OUTPUT_FILE" ]; then
    echo "Direct download failed (HTTP $HTTP_CODE), retrying through proxy..." >&2
    curl -s -o "$OUTPUT_FILE" --connect-timeout 15 --max-time 180 "$MEDIA_URL"
  fi

  if [ -s "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
    # Output Windows-native path for MEDIA: when running under WSL/Git Bash
    if [[ "$ORIGINAL_OUTPUT" =~ ^[A-Za-z]:[/\\] ]]; then
      MEDIA_PATH="$ORIGINAL_OUTPUT"
    else
      MEDIA_PATH=$(cd "$(dirname "$OUTPUT_FILE")" && pwd)/$(basename "$OUTPUT_FILE")
      MEDIA_PATH=$(unix_to_win_path "$MEDIA_PATH")
    fi
    echo "Downloaded: $MEDIA_PATH (${FILE_SIZE} bytes)" >&2
    echo "MEDIA:${MEDIA_PATH}"
  else
    echo "Error: download failed, file is empty" >&2
    echo "$RESULT"
    exit 1
  fi
else
  echo "$RESULT"
fi
