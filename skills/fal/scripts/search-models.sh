#!/bin/bash

# fal.ai Model Search Script
# Usage: ./search-models.sh [--query QUERY] [--category CATEGORY] [--limit N]

set -e

FAL_API_ENDPOINT="https://api.fal.ai/v1/models"
QUERY=""
CATEGORY=""
LIMIT=20

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --query|-q) QUERY="$2"; shift 2 ;;
    --category|-c) CATEGORY="$2"; shift 2 ;;
    --limit|-l) LIMIT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: ./search-models.sh [--query QUERY] [--category CATEGORY] [--limit N]" >&2
      echo "Categories: text-to-image, image-to-image, text-to-video, image-to-video" >&2
      exit 0
      ;;
    *) shift ;;
  esac
done

if [ -z "$FAL_KEY" ]; then echo "Error: FAL_KEY not set" >&2; exit 1; fi

PARAMS="limit=$LIMIT"
[ -n "$QUERY" ] && PARAMS="$PARAMS&q=$(echo "$QUERY" | sed 's/ /%20/g')"
[ -n "$CATEGORY" ] && PARAMS="$PARAMS&category=$CATEGORY"

echo "Searching fal.ai models..." >&2
curl -s -X GET "$FAL_API_ENDPOINT?$PARAMS" \
  -H "Content-Type: application/json" \
  -H "Authorization: Key $FAL_KEY"
