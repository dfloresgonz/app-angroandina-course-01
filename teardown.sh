#!/usr/bin/env bash
set -euo pipefail

log() { echo "[teardown] $*"; }
die() { echo "[teardown] ERROR: $*" >&2; exit 1; }

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

command -v aws    >/dev/null || die "aws CLI not found"
command -v gcloud >/dev/null || die "gcloud not found"
command -v jq     >/dev/null || die "jq not found"

PROJECT_NAME="angroandina-monitor"
AWS_REGION="us-east-1"
GCP_PROJECT="${GCP_PROJECT_ID:-utec-posgrado-01}"
STATE_BUCKET="${PROJECT_NAME}-tfstate-dev"

echo ""
echo "WARNING: Esto destruira TODA la infraestructura de $PROJECT_NAME:"
echo "   AWS: Lambda, DynamoDB, Kinesis, API GW, CloudFront, S3, Cognito, IAM"
echo "   GCP: Cloud Function, Pub/Sub, BigQuery, GCS"
echo "   Remote state: S3 bucket, DynamoDB lock, GCS bucket"
echo ""
read -r -p "Escribe 'yes' para confirmar: " confirm
[ "$confirm" = "yes" ] || { log "Aborted."; exit 0; }

# ── Terraform destroy (si hay state disponible) ────────────────────────────────
if command -v terraform >/dev/null 2>&1; then
  log "Intentando terraform destroy en AWS..."
  cd "$PROJECT_ROOT/infrastructure/aws"
  terraform init -input=false -upgrade=false >/dev/null 2>&1 || true
  terraform destroy -auto-approve -input=false \
    -var="kdg_username=placeholder" \
    -var="kdg_password=placeholder" \
    -var="gcp_forwarder_url=https://placeholder" 2>/dev/null || true
  cd "$PROJECT_ROOT"

  log "Intentando terraform destroy en GCP..."
  cd "$PROJECT_ROOT/infrastructure/gcp"
  terraform init -input=false -upgrade=false >/dev/null 2>&1 || true
  terraform destroy -auto-approve -input=false \
    -var="project_id=$GCP_PROJECT" 2>/dev/null || true
  cd "$PROJECT_ROOT"
fi

# ══════════════════════════════════════════════════════════════════════════════
# AWS — limpieza manual (cubre recursos que terraform pudo haber dejado)
# ══════════════════════════════════════════════════════════════════════════════

# ── Lambdas ───────────────────────────────────────────────────────────────────
log "Eliminando Lambda functions..."
for fn in ws-handler data-processor gcp-forwarder; do
  NAME="${PROJECT_NAME}-${fn}"
  if aws lambda get-function --function-name "$NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws lambda delete-function --function-name "$NAME" --region "$AWS_REGION"
    log "  Deleted $NAME"
  fi
done

# ── Kinesis ───────────────────────────────────────────────────────────────────
log "Eliminando Kinesis stream..."
STREAM="${PROJECT_NAME}-stream"
if aws kinesis describe-stream-summary --stream-name "$STREAM" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws kinesis delete-stream --stream-name "$STREAM" --region "$AWS_REGION"
  log "  Deleted $STREAM"
fi

# ── DynamoDB ──────────────────────────────────────────────────────────────────
log "Eliminando DynamoDB tables..."
for table in telemetry ws-connections; do
  NAME="${PROJECT_NAME}-${table}"
  if aws dynamodb describe-table --table-name "$NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws dynamodb delete-table --table-name "$NAME" --region "$AWS_REGION"
    log "  Deleted $NAME"
  fi
done

# ── API Gateway WebSocket ─────────────────────────────────────────────────────
log "Eliminando API Gateway WebSocket..."
API_IDS=$(aws apigatewayv2 get-apis --region "$AWS_REGION" \
  --query "Items[?starts_with(Name, '${PROJECT_NAME}')].ApiId" --output text)
for api_id in $API_IDS; do
  aws apigatewayv2 delete-api --api-id "$api_id" --region "$AWS_REGION"
  log "  Deleted API $api_id"
done

# ── CloudFront ────────────────────────────────────────────────────────────────
log "Eliminando CloudFront distribution..."
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?contains(Comment, '${PROJECT_NAME}')].Id" \
  --output text 2>/dev/null || echo "")

if [ -n "$DIST_ID" ]; then
  log "  Deshabilitando $DIST_ID (puede tardar ~5 min)..."
  ETAG=$(aws cloudfront get-distribution --id "$DIST_ID" --query 'ETag' --output text)
  aws cloudfront get-distribution-config --id "$DIST_ID" \
    --query 'DistributionConfig' > /tmp/cf-config.json
  python3 -c "
import json, sys
cfg = json.load(open('/tmp/cf-config.json'))
cfg['Enabled'] = False
json.dump(cfg, open('/tmp/cf-config.json','w'))
"
  aws cloudfront update-distribution --id "$DIST_ID" \
    --distribution-config file:///tmp/cf-config.json \
    --if-match "$ETAG" >/dev/null
  aws cloudfront wait distribution-deployed --id "$DIST_ID"
  ETAG=$(aws cloudfront get-distribution --id "$DIST_ID" --query 'ETag' --output text)
  aws cloudfront delete-distribution --id "$DIST_ID" --if-match "$ETAG"
  log "  Deleted CloudFront $DIST_ID"
fi

# ── S3 buckets ────────────────────────────────────────────────────────────────
log "Eliminando S3 buckets..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
for suffix in "frontend-${ACCOUNT_ID}" "deploy-${ACCOUNT_ID}"; do
  BUCKET="${PROJECT_NAME}-${suffix}"
  if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    aws s3 rb "s3://$BUCKET" --force
    log "  Deleted s3://$BUCKET"
  fi
done

# ── Cognito ───────────────────────────────────────────────────────────────────
log "Eliminando Cognito User Pool..."
POOL_IDS=$(aws cognito-idp list-user-pools --max-results 60 --region "$AWS_REGION" \
  --query "UserPools[?starts_with(Name, '${PROJECT_NAME}')].Id" --output text)
for pool_id in $POOL_IDS; do
  # eliminar clients primero
  CLIENT_IDS=$(aws cognito-idp list-user-pool-clients \
    --user-pool-id "$pool_id" --region "$AWS_REGION" \
    --query 'UserPoolClients[].ClientId' --output text)
  for client_id in $CLIENT_IDS; do
    aws cognito-idp delete-user-pool-client \
      --user-pool-id "$pool_id" --client-id "$client_id" --region "$AWS_REGION"
  done
  aws cognito-idp delete-user-pool --user-pool-id "$pool_id" --region "$AWS_REGION"
  log "  Deleted User Pool $pool_id"
done

# ── CloudFormation (KDG) ──────────────────────────────────────────────────────
log "Eliminando CloudFormation stack KDG..."
STACK="${PROJECT_NAME}-kdg-cognito"
if aws cloudformation describe-stacks --stack-name "$STACK" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws cloudformation delete-stack --stack-name "$STACK" --region "$AWS_REGION"
  aws cloudformation wait stack-delete-complete --stack-name "$STACK" --region "$AWS_REGION"
  log "  Deleted $STACK"
fi

# ── IAM roles ─────────────────────────────────────────────────────────────────
log "Eliminando IAM roles..."
ROLES=$(aws iam list-roles \
  --query "Roles[?starts_with(RoleName, '${PROJECT_NAME}')].RoleName" --output text)
for role in $ROLES; do
  aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text \
    | tr '\t' '\n' \
    | xargs -I{} aws iam delete-role-policy --role-name "$role" --policy-name {} 2>/dev/null || true
  aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text \
    | tr '\t' '\n' \
    | xargs -I{} aws iam detach-role-policy --role-name "$role" --policy-arn {} 2>/dev/null || true
  aws iam delete-role --role-name "$role"
  log "  Deleted role $role"
done

# ══════════════════════════════════════════════════════════════════════════════
# GCP — limpieza manual
# ══════════════════════════════════════════════════════════════════════════════

# ── Cloud Function ────────────────────────────────────────────────────────────
log "Eliminando Cloud Function..."
FN_NAME="${PROJECT_NAME}-telemetry-ingest"
if gcloud functions describe "$FN_NAME" --region=us-central1 --project="$GCP_PROJECT" >/dev/null 2>&1; then
  gcloud functions delete "$FN_NAME" --region=us-central1 --project="$GCP_PROJECT" --quiet
  log "  Deleted $FN_NAME"
fi

# ── Pub/Sub ───────────────────────────────────────────────────────────────────
log "Eliminando Pub/Sub topic..."
TOPIC="${PROJECT_NAME}-telemetry"
if gcloud pubsub topics describe "$TOPIC" --project="$GCP_PROJECT" >/dev/null 2>&1; then
  gcloud pubsub topics delete "$TOPIC" --project="$GCP_PROJECT" --quiet
  log "  Deleted topic $TOPIC"
fi

# ── BigQuery ──────────────────────────────────────────────────────────────────
log "Eliminando BigQuery dataset..."
BQ_DATASET="${PROJECT_NAME//-/_}_monitor"
if bq show --project_id="$GCP_PROJECT" "$GCP_PROJECT:$BQ_DATASET" >/dev/null 2>&1; then
  bq rm -r -f "$GCP_PROJECT:$BQ_DATASET"
  log "  Deleted dataset $BQ_DATASET"
fi

# ── GCS function source bucket ────────────────────────────────────────────────
log "Eliminando GCS function source bucket..."
SRC_BUCKET="${PROJECT_NAME}-function-source-${GCP_PROJECT}"
if gcloud storage buckets describe "gs://$SRC_BUCKET" --project="$GCP_PROJECT" >/dev/null 2>&1; then
  gcloud storage rm -r "gs://$SRC_BUCKET" --quiet
  log "  Deleted gs://$SRC_BUCKET"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Remote state
# ══════════════════════════════════════════════════════════════════════════════

# ── S3 state bucket ───────────────────────────────────────────────────────────
log "Eliminando remote state S3 (s3://$STATE_BUCKET)..."
if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  aws s3api list-object-versions --bucket "$STATE_BUCKET" \
    --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null \
  | jq -r '.[] | "\(.Key) \(.VersionId)"' \
  | while read -r key vid; do
      aws s3api delete-object --bucket "$STATE_BUCKET" --key "$key" --version-id "$vid" >/dev/null
    done 2>/dev/null || true

  aws s3api list-object-versions --bucket "$STATE_BUCKET" \
    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null \
  | jq -r '.[] | "\(.Key) \(.VersionId)"' \
  | while read -r key vid; do
      aws s3api delete-object --bucket "$STATE_BUCKET" --key "$key" --version-id "$vid" >/dev/null
    done 2>/dev/null || true

  aws s3api delete-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION"
  log "  Deleted s3://$STATE_BUCKET"
else
  log "  S3 state bucket no existe, omitiendo."
fi

# ── DynamoDB lock ─────────────────────────────────────────────────────────────
log "Eliminando DynamoDB lock table..."
LOCK_TABLE="${PROJECT_NAME}-tfstate-lock-dev"
if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws dynamodb delete-table --table-name "$LOCK_TABLE" --region "$AWS_REGION"
  log "  Deleted $LOCK_TABLE"
else
  log "  Lock table no existe, omitiendo."
fi

# ── GCS state bucket ──────────────────────────────────────────────────────────
log "Eliminando remote state GCS (gs://$STATE_BUCKET)..."
if gcloud storage buckets describe "gs://$STATE_BUCKET" >/dev/null 2>&1; then
  gcloud storage rm -r "gs://$STATE_BUCKET" --quiet
  log "  Deleted gs://$STATE_BUCKET"
else
  log "  GCS state bucket no existe, omitiendo."
fi

# ── Artefactos locales ────────────────────────────────────────────────────────
log "Limpiando artefactos locales..."
rm -rf "$PROJECT_ROOT/.lambda-zips"
rm -f  "$PROJECT_ROOT/frontend/js/config.js"

log ""
log "Teardown completo. Todo eliminado."
