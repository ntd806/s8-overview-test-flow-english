#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"
docker compose -f docker-compose.node22.yml run --rm bacay-node22-script "$@"
