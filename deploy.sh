#!/usr/bin/env bash
set -euo pipefail

# ─── helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[deploy] $*"; }
die()  { echo "[deploy] ERROR: $*" >&2; exit 1; }

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
ZIPS_DIR="$PROJECT_ROOT/.lambda-zips"
LAMBDAS_DIR="$PROJECT_ROOT/app/lambdas"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

# ─── 0. preflight ──────────────────────────────────────────────────────────────
command -v terraform >/dev/null || die "terraform not found"
command -v aws       >/dev/null || die "aws CLI not found"
command -v gcloud    >/dev/null || die "gcloud not found"
command -v jq        >/dev/null || die "jq not found"

# ─── 1. zip lambdas ────────────────────────────────────────────────────────────
log "Zipping Lambda functions…"
mkdir -p "$ZIPS_DIR"

for fn in ws-handler data-processor gcp-forwarder; do
  src="$LAMBDAS_DIR/$fn"
  zip="$ZIPS_DIR/$fn.zip"
  [ -d "$src" ] || die "Lambda source not found: $src"
  cd "$src"
  # install prod deps if package.json present and node_modules missing
  if [ -f package.json ] && [ ! -d node_modules ]; then
    log "  npm ci --omit=dev ($fn)"
    npm ci --omit=dev
  fi
  zip -qr "$zip" . --exclude "*.test.*" "*.spec.*"
  cd "$PROJECT_ROOT"
  log "  ✓ $fn.zip"
done

# ─── 2. GCP infra ──────────────────────────────────────────────────────────────
log "Deploying GCP infrastructure…"
cd "$PROJECT_ROOT/infrastructure/gcp"
terraform init -input=false
terraform apply -auto-approve -input=false

GCP_FUNCTION_URL=$(terraform output -raw function_url)
log "  GCP Cloud Function URL: $GCP_FUNCTION_URL"
cd "$PROJECT_ROOT"

# ─── 3. AWS infra ──────────────────────────────────────────────────────────────
log "Deploying AWS infrastructure…"
cd "$PROJECT_ROOT/infrastructure/aws"
terraform init -input=false

# pass gcp_forwarder_url if not already in tfvars
TF_VARS="-var=gcp_forwarder_url=$GCP_FUNCTION_URL"
terraform apply -auto-approve -input=false $TF_VARS

CLOUDFRONT_URL=$(terraform output -raw cloudfront_url)
WS_ENDPOINT=$(terraform output -raw ws_endpoint)
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name)
DISTRIBUTION_ID=$(terraform output -raw distribution_id)
COGNITO_POOL_ID=$(terraform output -raw cognito_user_pool_id)
COGNITO_CLIENT_ID=$(terraform output -raw cognito_client_id)
log "  CloudFront: $CLOUDFRONT_URL"
log "  WebSocket:  $WS_ENDPOINT"
log "  Cognito:    $COGNITO_POOL_ID"
cd "$PROJECT_ROOT"

# ─── 4. frontend config ────────────────────────────────────────────────────────
log "Generating frontend/js/config.js…"
cat > "$FRONTEND_DIR/js/config.js" <<EOF
window.AGRO_CONFIG = {
  wsUrl:      '$WS_ENDPOINT',
  userPoolId: '$COGNITO_POOL_ID',
  clientId:   '$COGNITO_CLIENT_ID'
};
EOF

# ─── 5. sync frontend to S3 ───────────────────────────────────────────────────
log "Syncing frontend to S3…"
aws s3 sync "$FRONTEND_DIR" "s3://$FRONTEND_BUCKET" \
  --delete \
  --cache-control "no-cache, no-store, must-revalidate" \
  --exclude "*.DS_Store"

# ─── 6. CloudFront invalidation ───────────────────────────────────────────────
log "Invalidating CloudFront cache…"
aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" \
  --query 'Invalidation.Id' --output text

log ""
log "✅ Deploy complete!"
log "   Dashboard → https://$CLOUDFRONT_URL"
log "   WebSocket → $WS_ENDPOINT"
