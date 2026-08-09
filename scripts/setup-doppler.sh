#!/bin/bash

set -euo pipefail

PROJECT="notenerds"
CONFIG="prd"

if ! command -v doppler >/dev/null 2>&1; then
    echo "Doppler CLI is required. Install it with: brew install dopplerhq/cli/doppler" >&2
    exit 1
fi

if ! doppler me >/dev/null 2>&1; then
    echo "Doppler authentication is required. Run: doppler login" >&2
    exit 1
fi

if ! doppler projects get "$PROJECT" >/dev/null 2>&1; then
    doppler projects create "$PROJECT" \
        --description "Build and App Store release credentials for Note Nerds"
fi

if ! doppler configs get "$CONFIG" --project "$PROJECT" >/dev/null 2>&1; then
    doppler configs create "$CONFIG" --project "$PROJECT" --environment prd
fi

doppler setup --project "$PROJECT" --config "$CONFIG" --no-interactive

echo "Doppler project ready: $PROJECT/$CONFIG"
echo "Add ASC_KEY_ID, ASC_ISSUER_ID, and ASC_APP_ID after creating the app and API key."
