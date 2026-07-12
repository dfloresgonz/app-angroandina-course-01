# AngroAndina Monitor

Dashboard IoT en tiempo real para AgroAndina Fresh S.A.C.
Arquitectura multi-cloud: **AWS** (ingesta + WebSocket) + **GCP** (analítica).

---

## Prerequisitos locales

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.7
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configurado con credenciales
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`brew install --cask google-cloud-sdk`)
- Node.js 24
- `jq`

---

## Primer deploy (desde cero)

### 1. Configurar GCP

```bash
gcloud init
# Elegir proyecto: utec-posgrado-01
# Región: us-central1 / Zona: us-central1-a

gcloud auth application-default login
gcloud config set project utec-posgrado-01
```

### 2. Crear Service Account para CI/CD

```bash
PROJECT_ID="utec-posgrado-01"
SA="angroandina-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create angroandina-deployer \
  --display-name "AngroAndina Terraform Deployer"

for role in roles/pubsub.admin roles/bigquery.admin \
            roles/cloudfunctions.admin roles/storage.admin \
            roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA" --role="$role"
done

gcloud iam service-accounts keys create gcp-key.json --iam-account=$SA
```

Guarda el contenido de `gcp-key.json` como secret `GCP_SA_KEY` en GitHub (Settings → Secrets → Actions).
**No subas `gcp-key.json` al repositorio.**

### 3. Configurar secrets en GitHub

| Secret | Descripción |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | Access key de AWS |
| `AWS_SECRET_ACCESS_KEY` | Secret key de AWS |
| `GCP_SA_KEY` | Contenido completo de `gcp-key.json` |
| `GCP_PROJECT_ID` | `utec-posgrado-01` |
| `KDG_USERNAME` | Usuario para Kinesis Data Generator |
| `KDG_PASSWORD` | Password para KDG |

### 4. Bootstrap del remote state (una sola vez)

```bash
export GCP_PROJECT_ID="utec-posgrado-01"
./bootstrap-state.sh
```

Crea:
- S3 bucket `angroandina-monitor-tfstate` + tabla DynamoDB `angroandina-tfstate-lock` (AWS)
- GCS bucket `angroandina-monitor-tfstate` (GCP)

### 5. Deploy

```bash
git push origin main
```

El pipeline de GitHub Actions despliega todo automáticamente.
Al finalizar, la URL del dashboard aparece en el Job Summary de Actions.

### 6. Crear primer usuario del dashboard

```bash
aws cognito-idp admin-create-user \
  --user-pool-id <pool-id-del-output-de-terraform> \
  --username tu@email.com \
  --temporary-password "Temp123!" \
  --message-action SUPPRESS
```

El usuario deberá cambiar su contraseña en el primer login.

---

## Deploy solo del frontend

```bash
./deploy-frontend.sh
```

---

## Destruir todo

```bash
./teardown.sh
```

Destruye en orden: recursos AWS → recursos GCP → remote state (S3, DynamoDB, GCS).

---

## Estructura del proyecto

```
.
├── .github/workflows/deploy.yml   # Pipeline CI/CD
├── app/lambdas/
│   ├── ws-handler/                # Maneja conexiones WebSocket
│   ├── data-processor/            # Procesa Kinesis → DynamoDB + WebSocket + GCP
│   └── gcp-forwarder/             # Reenvía datos a GCP Cloud Function
├── frontend/
│   ├── index.html                 # Dashboard principal
│   ├── login.html                 # Login con Cognito
│   ├── css/styles.css
│   └── js/
│       ├── app.js                 # Entry point
│       ├── auth.js                # Autenticación Cognito (vanilla JS)
│       ├── charts.js              # 6 gráficos Chart.js
│       ├── websocket.js           # WebSocket con reconexión exponencial
│       └── config.js              # Generado por deploy.sh (no en repo)
├── gcp-functions/telemetry-ingest # Cloud Function → BigQuery
├── infrastructure/
│   ├── aws/                       # Terraform AWS
│   └── gcp/                       # Terraform GCP
├── bootstrap-state.sh             # Crea backends de Terraform (ejecutar una vez)
├── deploy.sh                      # Deploy completo local
├── deploy-frontend.sh             # Re-deploy solo frontend
├── teardown.sh                    # Destruye toda la infraestructura
└── kdg-template.json              # Template para Kinesis Data Generator
```
