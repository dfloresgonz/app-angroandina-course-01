#!/usr/bin/env bash
set -euo pipefail

log() { echo "[frontend] $*"; }
die() { echo "[frontend] ERROR: $*" >&2; exit 1; }

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

command -v aws >/dev/null || die "aws CLI not found"
command -v terraform >/dev/null || die "terraform not found"

cd "$PROJECT_ROOT/infrastructure/aws"
terraform init -input=false -upgrade=false >/dev/null

CLOUDFRONT_URL=$(terraform output -raw cloudfront_url)
WS_ENDPOINT=$(terraform output -raw ws_endpoint)
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name)
DISTRIBUTION_ID=$(terraform output -raw distribution_id)
COGNITO_POOL_ID=$(terraform output -raw cognito_user_pool_id)
COGNITO_CLIENT_ID=$(terraform output -raw cognito_client_id)

log "Generating config.js…"
cat > "$FRONTEND_DIR/js/config.js" <<EOF
window.AGRO_CONFIG = {
  wsUrl:      '$WS_ENDPOINT',
  userPoolId: '$COGNITO_POOL_ID',
  clientId:   '$COGNITO_CLIENT_ID'
};
EOF

log "Syncing to s3://$FRONTEND_BUCKET…"
aws s3 sync "$FRONTEND_DIR" "s3://$FRONTEND_BUCKET" \
  --delete \
  --cache-control "no-cache, no-store, must-revalidate" \
  --exclude "*.DS_Store"

log "Invalidating CloudFront ($DISTRIBUTION_ID)…"
INVAL_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" \
  --query 'Invalidation.Id' --output text)
log "  Invalidation $INVAL_ID in progress"

log ""
log "✅ Frontend deployed → https://$CLOUDFRONT_URL"
