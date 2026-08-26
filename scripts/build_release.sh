#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST/package"
cp -r "$ROOT/src" "$ROOT/init.lua" "$ROOT/info.json" "$ROOT/LICENSE" "$ROOT/SECURITY.md" "$DIST/package/"
cd "$DIST/package"
EPOCH="${SOURCE_DATE_EPOCH:-1704067200}"
find . -exec touch -h -d "@$EPOCH" {} +
LC_ALL=C find . -type f | sort > ../manifest.txt
TZ=UTC zip -X -q "../chatterino-kick-chat-$VERSION.zip" -@ < ../manifest.txt
cd "$DIST"
sha256sum "chatterino-kick-chat-$VERSION.zip" > "chatterino-kick-chat-$VERSION.zip.sha256"
echo "$DIST/chatterino-kick-chat-$VERSION.zip"
