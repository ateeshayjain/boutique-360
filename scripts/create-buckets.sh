#!/usr/bin/env bash
# Plan 1, Task 1.17 — create Supabase Storage buckets (idempotent)
set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
SERVICE_KEY="${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY required}"

create_bucket() {
  local id="$1"
  local public="$2"
  local resp
  resp=$(curl -sS -o /tmp/bucket_resp -w "%{http_code}" -X POST "${SUPABASE_URL}/storage/v1/bucket" \
    -H "Authorization: Bearer ${SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"${id}\",\"name\":\"${id}\",\"public\":${public}}")
  case "$resp" in
    200|201) echo "  ✓ created $id";;
    409)     echo "  ⊙ $id already exists";;
    *)       echo "  ✗ $id failed (HTTP $resp): $(cat /tmp/bucket_resp)"; exit 1;;
  esac
}

echo "Creating storage buckets at ${SUPABASE_URL} ..."
create_bucket "product-images"     "true"
create_bucket "vto-uploads"        "false"
create_bucket "vto-results"        "true"
create_bucket "design-sketches"    "false"
create_bucket "design-renders"     "false"
create_bucket "customer-photos"    "false"
create_bucket "fabrics"            "false"
create_bucket "invoices"           "false"
create_bucket "measurements-photos" "false"
echo "All buckets configured."
