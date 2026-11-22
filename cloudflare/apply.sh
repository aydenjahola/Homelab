#!/usr/bin/env bash
# Run OpenTofu for the Cloudflare config with credentials pulled from Consul.
#   ./apply.sh init | plan | apply | ...
# The API token never touches the command line or disk (Falco logs argv).
set -euo pipefail
cd "$(dirname "$0")"

export CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://192.168.1.100:8500}"
CLOUDFLARE_API_TOKEN="$(consul kv get cloudflare/terraform/token)"
export CLOUDFLARE_API_TOKEN

exec tofu "$@"
