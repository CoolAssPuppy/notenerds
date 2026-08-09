#!/bin/bash

set -euo pipefail

version="${1:?XcodeGen version is required}"
expected_sha256="${2:?XcodeGen SHA-256 is required}"
install_root="${3:?Install directory is required}"
download_directory="$(mktemp -d)"
archive="$download_directory/xcodegen.zip"

cleanup() {
    rm -rf "$download_directory"
}
trap cleanup EXIT

curl --fail --silent --show-error --location \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip" \
    --output "$archive"
printf '%s  %s\n' "$expected_sha256" "$archive" | shasum -a 256 --check
unzip -q "$archive" -d "$download_directory"
mkdir -p "$install_root"
PREFIX="$install_root" bash "$download_directory/xcodegen/install.sh"
"$install_root/bin/xcodegen" --version
