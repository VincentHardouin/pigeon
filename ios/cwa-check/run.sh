#!/bin/sh
# Checks the CWA upload logic (GET before PUT, skip when server is newer, 401) against a fake local CWA. Run from anywhere on macOS.
# Uses the login keychain item "cwa" and ~/Library/Application Support/progress.json, both removed at the end.
set -e
cd "$(dirname "$0")"
python3 fake_cwa.py & SERVER=$!
trap 'kill $SERVER; rm -f "$HOME/Library/Application Support/progress.json" cwatest' EXIT
sleep 1
swiftc -swift-version 5 -target arm64-apple-macosx14.0 ../Pigeon/Store.swift ../Pigeon/CWA.swift main.swift -o cwatest
./cwatest
