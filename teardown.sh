#!/usr/bin/env bash
set -euo pipefail

log() { echo "[teardown] $*"; }
die() { echo "[teardown] ERROR: $*" >&2; exit 1; }

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

command -v terraform >/dev/null || die "terraform not found"
command -v aws       >/dev/null || die "aws CLI not found"
command -v gcloud    >/dev/null || die "gcloud not found"

STATE_BUCKET="angroandina-monitor-tfstate"

echo "⚠️  Esto destruirá TODA la infraestructura de angroandina-monitor:"
echo "   • Recursos AWS (Lambda, DynamoDB, API GW, CloudFront, S3, Cognito, Kinesis)"
echo "   • Recursos GCP (Cloud Function, Pub/Sub, BigQuery, GCS)"
echo "   • Remote state (S3 bucket, DynamoDB lock, GCS bucket)"
echo ""
read -r -p "Escribe 'yes' para confirmar: " confirm
[ "$confirm" = "yes" ] || { log "Aborted."; exit 0; }

# ─── 1. Vaciar S3 buckets de la app (terraform destroy falla si no están vacíos) ──
log "Leyendo buckets desde Terraform state…"
cd "$PROJECT_ROOT/infrastructure/aws"
terraform init -input=false -upgrade=false >/dev/null 2>&1 || true

FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name 2>/dev/null || echo "")
DEPLOY_BUCKET=$(terraform output -raw deploy_bucket_name 2>/dev/null || echo "")

for bucket in "$FRONTEND_BUCKET" "$DEPLOY_BUCKET"; do
  if [ -n "$bucket" ]; then
    log "Vaciando s3://$bucket…"
    aws s3 rm "s3://$bucket" --recursive || true
  fi
done

# ─── 2. Destroy AWS ────────────────────────────────────────────────────────────
log "Destruyendo infraestructura AWS…"
terraform destroy -auto-approve -input=false || true
cd "$PROJECT_ROOT"

# ─── 3. Destroy GCP ────────────────────────────────────────────────────────────
log "Destruyendo infraestructura GCP…"
cd "$PROJECT_ROOT/infrastructure/gcp"
terraform init -input=false -upgrade=false >/dev/null 2>&1 || true
terraform destroy -auto-approve -input=false || true
cd "$PROJECT_ROOT"

# ─── 4. Vaciar y eliminar remote state S3 ─────────────────────────────────────
log "Eliminando remote state S3 (s3://$STATE_BUCKET)…"
if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  # Eliminar todas las versiones (bucket tiene versioning)
  aws s3api list-object-versions --bucket "$STATE_BUCKET" \
    --query 'Versions[].{Key:Key,VersionId:VersionId}' \
    --output json 2>/dev/null \
  | jq -r '.[] | "\(.Key) \(.VersionId)"' \
  | while read -r key vid; do
      aws s3api delete-object --bucket "$STATE_BUCKET" --key "$key" --version-id "$vid" >/dev/null
    done || true

  aws s3api list-object-versions --bucket "$STATE_BUCKET" \
    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
    --output json 2>/dev/null \
  | jq -r '.[] | "\(.Key) \(.VersionId)"' \
  | while read -r key vid; do
      aws s3api delete-object --bucket "$STATE_BUCKET" --key "$key" --version-id "$vid" >/dev/null
    done || true

  aws s3api delete-bucket --bucket "$STATE_BUCKET" --region us-east-1
  log "  ✓ S3 bucket eliminado"
else
  log "  S3 bucket no existe, omitiendo."
fi

# ─── 5. Eliminar DynamoDB lock table ──────────────────────────────────────────
log "Eliminando DynamoDB lock table…"
if aws dynamodb describe-table --table-name angroandina-tfstate-lock \
   --region us-east-1 >/dev/null 2>&1; then
  aws dynamodb delete-table \
    --table-name angroandina-tfstate-lock \
    --region us-east-1
  log "  ✓ DynamoDB tabla eliminada"
else
  log "  Tabla no existe, omitiendo."
fi

# ─── 6. Eliminar GCS bucket de remote state ───────────────────────────────────
log "Eliminando remote state GCS (gs://$STATE_BUCKET)…"
if gcloud storage buckets describe "gs://$STATE_BUCKET" >/dev/null 2>&1; then
  gcloud storage rm -r "gs://$STATE_BUCKET" || true
  log "  ✓ GCS bucket eliminado"
else
  log "  GCS bucket no existe, omitiendo."
fi

# ─── 7. Limpiar artefactos locales ────────────────────────────────────────────
log "Limpiando artefactos locales…"
rm -rf "$PROJECT_ROOT/.lambda-zips"
rm -f  "$PROJECT_ROOT/frontend/js/config.js"

log ""
log "✅ Teardown completo. Todo eliminado."
