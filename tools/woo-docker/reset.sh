#!/usr/bin/env bash
# Destroys the throwaway local store completely (containers + volumes), then recreates it.
set -euo pipefail
cd "$(dirname "$0")"
docker compose down -v
./setup.sh
