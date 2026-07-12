#!/usr/bin/env bash
# Crea los backends de Terraform remote state ANTES del primer deploy.
# Ejecutar una sola vez: ./bootstrap-state.sh
set -euo pipefail

log() { echo "[bootstrap] $*"; }
die() { echo "[bootstrap] ERROR: $*" >&2; exit 1; }

command -v aws    >/dev/null || die "aws CLI not found"
command -v gcloud >/dev/null || die "gcloud not found"

AWS_REGION="us-east-1"
GCP_PROJECT="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

[ -n "$GCP_PROJECT" ] || die "GCP_PROJECT_ID no está definido. Exporta: export GCP_PROJECT_ID=utec-posgrado-01"

# Nombre único para el bucket (igual en AWS y GCS — cambia si ya existe)
STATE_BUCKET="angroandina-monitor-tfstate"

# ─── AWS: S3 bucket + DynamoDB lock table ────────────────────────────────────
log "Creando S3 bucket para Terraform state: $STATE_BUCKET"
if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  log "  El bucket ya existe, omitiendo."
else
  aws s3api create-bucket \
    --bucket "$STATE_BUCKET" \
    --region "$AWS_REGION"

  aws s3api put-bucket-versioning \
    --bucket "$STATE_BUCKET" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption \
    --bucket "$STATE_BUCKET" \
    --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

  aws s3api put-public-access-block \
    --bucket "$STATE_BUCKET" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  log "  ✓ S3 bucket creado"
fi

log "Creando DynamoDB tabla para state locking: angroandina-tfstate-lock"
if aws dynamodb describe-table --table-name angroandina-tfstate-lock \
   --region "$AWS_REGION" >/dev/null 2>&1; then
  log "  La tabla ya existe, omitiendo."
else
  aws dynamodb create-table \
    --table-name angroandina-tfstate-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION"
  log "  ✓ DynamoDB tabla creada"
fi

# ─── GCP: GCS bucket ─────────────────────────────────────────────────────────
log "Creando GCS bucket para Terraform state: $STATE_BUCKET"
if gcloud storage buckets describe "gs://$STATE_BUCKET" >/dev/null 2>&1; then
  log "  El bucket ya existe, omitiendo."
else
  gcloud storage buckets create "gs://$STATE_BUCKET" \
    --project="$GCP_PROJECT" \
    --location=US \
    --uniform-bucket-level-access
  log "  ✓ GCS bucket creado"
fi

log ""
log "✅ Bootstrap completo."
log "   AWS  → s3://$STATE_BUCKET  +  DynamoDB angroandina-tfstate-lock"
log "   GCP  → gs://$STATE_BUCKET"
log ""
log "Ahora puedes correr: ./deploy.sh"
