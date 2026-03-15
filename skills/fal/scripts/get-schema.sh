#!/bin/bash

# fal.ai Model Schema Script
# Usage: ./get-schema.sh --model MODEL [--input] [--output]

set -e

MODEL=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --model|-m) MODEL="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: ./get-schema.sh --model MODEL" >&2
      exit 0
      ;;
    *) shift ;;
  esac
done

if [ -z "$MODEL" ]; then echo "Error: --model required" >&2; exit 1; fi

ENCODED=$(echo "$MODEL" | sed 's/\//%2F/g')
echo "Fetching schema for $MODEL..." >&2
curl -s "https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=$ENCODED"
