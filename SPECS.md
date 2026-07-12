# angroandina-monitor — Project Specifications

## Overview

Real-time IoT sensor monitoring dashboard for AgroAndina Fresh S.A.C. Streams mock sensor telemetry through AWS Kinesis Data Generator (KDG), processes it via Lambda, stores it in DynamoDB, and pushes live updates to a browser dashboard via WebSocket. A forwarder Lambda reenvía cada registro a GCP Pub/Sub for historical analytics in BigQuery, visualized in Looker Studio. Static assets are served through CloudFront + S3. Infrastructure is managed with Terraform across both clouds.

---

## Goals

- Demonstrate a real-time multi-cloud streaming pipeline: AWS for ingestion and live dashboard, GCP for analytics
- Provide a live dashboard with sensor charts updating via WebSocket
- Provide a historical analytics view via BigQuery + Looker Studio
- Keep infrastructure as code (Terraform), modularized per cloud provider
- Single repository, deployable via a single `deploy.sh` script

---

## Constraints

- AWS Region: `us-east-1`
- GCP Region: `us-central1`
- IaC: Terraform only (no CloudFormation, no CDK)
- Frontend: Vanilla JS (modern ES modules), Chart.js, no frameworks
- Lambdas: Node.js 22.x (ESM)
- GCP Cloud Function: Node.js 20.x
- No comments in code unless strictly necessary
- No emojis
- Tags on all AWS resources:
  ```
  ProjectName  = angroandina-monitor
  Environment  = dev
  ManagedBy    = terraform
  ```
- Labels on all GCP resources (GCP requires lowercase keys):
  ```
  project_name = angroandina-monitor
  environment  = dev
  managed_by   = terraform
  ```
- Every resource in every Terraform file must carry these tags/labels — no exceptions
- Do not build anything not explicitly required by this spec

---

## Repository Structure

```
angroandina-monitor/
├── infrastructure/
│   ├── aws/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── kinesis.tf
│   │   ├── dynamodb.tf
│   │   ├── cognito.tf
│   │   ├── iam.tf
│   │   ├── compute.tf
│   │   ├── s3.tf
│   │   └── cloudfront.tf
│   └── gcp/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── pubsub.tf
│       ├── bigquery.tf
│       └── functions.tf
├── app/
│   └── lambdas/
│       ├── data-processor/
│       │   └── index.mjs
│       ├── ws-handler/
│       │   └── index.mjs
│       └── gcp-forwarder/
│           └── index.mjs
├── gcp-functions/
│   └── telemetry-ingest/
│       ├── index.js
│       └── package.json
├── frontend/
│   ├── index.html
│   ├── assets/
│   │   └── logo.svg
│   ├── css/
│   │   └── styles.css
│   └── js/
│       ├── app.js
│       ├── websocket.js
│       ├── charts.js
│       └── config.js
├── deploy.sh
├── deploy-frontend.sh
├── teardown.sh
├── kdg-template.json
└── SPECS.md
```

---

## Architecture

```
[Kinesis Data Generator (KDG web UI)]
  └── authenticated via Cognito (Username + Password from deploy params)
        │
        ▼
[Kinesis Data Stream]
        │
        ▼
[data-processor Lambda] ──→ [DynamoDB: angroandina-telemetry]
        │                          │
        │                   [gcp-forwarder Lambda] ──→ [GCP Pub/Sub]
        │                                                     │
        │                                          [Cloud Function: telemetry-ingest]
        │                                                     │
        │                                              [BigQuery: telemetry]
        │                                                     │
        │                                           [Looker Studio dashboard]
        │
        └──→ [API Gateway WebSocket] ──→ [Browser: live dashboard]
               (scans angroandina-ws-connections, POSTs to each connectionId)

[ws-handler Lambda] ──→ [DynamoDB: angroandina-ws-connections]
  (handles $connect / $disconnect routes on the same WebSocket API)

[Browser]
  ├── Assets from CloudFront → S3 (no auth)
  └── Live data from API Gateway WebSocket (no auth)
```

---

## Infrastructure — AWS (`infrastructure/aws/`)

### `main.tf`
- Root Terraform config for AWS
- Provider: `aws`, region `us-east-1`
- Calls all AWS modules
- Outputs: `cloudfront_url`, `ws_endpoint`, `kdg_url`, `kinesis_stream_name`, `frontend_bucket_name`, `distribution_id`

### `variables.tf`
- `project_name` (default: `angroandina-monitor`)
- `environment` (default: `dev`)
- `kdg_username`
- `kdg_password` (sensitive)
- `gcp_forwarder_url` — URL of the GCP Pub/Sub HTTP endpoint (output from GCP deploy)

### `kinesis.tf`
- `aws_kinesis_stream`: name `angroandina-stream`, shard count = 1, tagged

### `dynamodb.tf`
- Table: `angroandina-telemetry`
  - Partition key: `sensor_id` (String)
  - Sort key: `timestamp` (String, ISO ms from KDG `date.now`)
  - TTL attribute: `expiresAt` (epoch seconds, now + 3h)
- Table: `angroandina-ws-connections`
  - Partition key: `connectionId` (String)

### `cognito.tf`
- Wraps the KDG Cognito setup via `aws_cloudformation_stack` resource pointing to:
  `https://aws-kdg-tools.s3.us-west-2.amazonaws.com/cognito-setup.yaml`
- Parameters: `Username`, `Password`
- Output: `kdg_url`

### `iam.tf`
- `data_processor_role`: Kinesis read, DynamoDB PutItem on telemetry, Scan+DeleteItem on ws-connections, `execute-api:ManageConnections`, Lambda invoke on gcp-forwarder
- `ws_handler_role`: DynamoDB PutItem+DeleteItem on ws-connections
- `gcp_forwarder_role`: DynamoDB GetItem on telemetry, basic Lambda execution

### `compute.tf`
- `ws_handler` Lambda: handles `$connect`, `$disconnect`, `$default`
- `ws_api`: API Gateway WebSocket, routes wired to ws-handler
- `ws_stage`: auto-deploy true
- `data_processor` Lambda: triggered by Kinesis, env vars `WS_ENDPOINT`, `TELEMETRY_TABLE`, `WS_CONNECTIONS_TABLE`, `GCP_FORWARDER_ARN`
- `gcp_forwarder` Lambda: invoked async by data-processor, env vars `GCP_PUBSUB_URL`, `GCP_PUBSUB_TOKEN`
- `kinesis_event_source`: BatchSize=10, StartingPosition=LATEST

### `s3.tf`
- Bucket: `angroandina-monitor-frontend-{account_id}`
- Block all public access (CloudFront only)

### `cloudfront.tf`
- Distribution with S3 origin, OAC
- Default root object: `index.html`
- Custom error: 404 → `/index.html`

---

## Infrastructure — GCP (`infrastructure/gcp/`)

### `main.tf`
- Provider: `google`, project from var, region `us-central1`
- Outputs: `pubsub_topic`, `bigquery_dataset`, `bigquery_table`, `function_url`

### `variables.tf`
- `project_id` — GCP project ID
- `project_name` (default: `angroandina-monitor`)
- `environment` (default: `dev`)
- `region` (default: `us-central1`)

### `pubsub.tf`
- `google_pubsub_topic`: name `angroandina-telemetry`
- `google_pubsub_subscription`: name `angroandina-telemetry-sub`, push to Cloud Function URL

### `bigquery.tf`
- Dataset: `angroandina_monitor`
- Table: `telemetry`
  - Schema: `sensor_id` STRING, `timestamp` TIMESTAMP, `temperature` FLOAT, `humidity` FLOAT, `soil_moisture` FLOAT, `light_intensity` FLOAT, `wind_speed` FLOAT, `battery_level` FLOAT, `received_at` TIMESTAMP
  - Partitioning by `timestamp` (DAY)

### `functions.tf`
- `google_cloudfunctions_function`: `telemetry-ingest`
  - Runtime: nodejs20
  - Trigger: Pub/Sub topic `angroandina-telemetry`
  - Entry point: `ingestTelemetry`
  - Env vars: `BIGQUERY_DATASET`, `BIGQUERY_TABLE`

---

## Lambda Details

### `data-processor`
- **Trigger**: Kinesis Data Stream (`angroandina-stream`)
- **Input**: batch of Kinesis records (base64-encoded JSON telemetry)
- **Logic**:
  - Decode each record (base64 → JSON)
  - Add `expiresAt` field (epoch seconds, `Math.floor(Date.now()/1000) + 10800`)
  - Write item to `angroandina-telemetry` with PK=`sensor_id`, SK=`timestamp`
  - Scan `angroandina-ws-connections` to get all active connection IDs
  - POST the telemetry JSON to each `connectionId` via API GW Management API
  - On 410 Gone: delete the stale connection from `angroandina-ws-connections`, continue
  - Invoke `gcp-forwarder` Lambda asynchronously (InvocationType=Event) with the raw record

### `ws-handler`
- **Trigger**: API Gateway WebSocket routes
- **Routes**:
  - `$connect`: write `connectionId` to `angroandina-ws-connections`
  - `$disconnect`: delete `connectionId` from `angroandina-ws-connections`
  - `$default`: no-op, return 200

### `gcp-forwarder`
- **Trigger**: invoked async by `data-processor`
- **Input**: single telemetry record JSON
- **Logic**:
  - POST record to GCP Pub/Sub REST API using a service account token from env var
  - No retry logic — fire and forget (Pub/Sub handles redelivery)

---

## GCP Cloud Function

### `telemetry-ingest`
- **Trigger**: Pub/Sub push subscription (`angroandina-telemetry-sub`)
- **Input**: Pub/Sub message with base64-encoded telemetry JSON
- **Logic**:
  - Decode message data (base64 → JSON)
  - Add `received_at` field (current UTC timestamp)
  - Insert row into BigQuery table `angroandina_monitor.telemetry`

---

## Kinesis Data Generator Setup

After deploying, open the KDG URL and configure:

- **Stream**: `angroandina-stream`
- **Region**: `us-east-1`
- **Records per second**: 5–10 (demo rate)
- **Template**: paste the contents of `kdg-template.json`

```json
{
  "timestamp": "{{date.now}}",
  "sensor_id": "{{random.arrayElement(["SENSOR_01","SENSOR_02","SENSOR_03","SENSOR_04","SENSOR_05"])}}",
  "temperature": {{random.number({"min":12,"max":38,"precision":0.1})}},
  "humidity": {{random.number({"min":30,"max":95,"precision":0.1})}},
  "soil_moisture": {{random.number({"min":10,"max":80,"precision":0.1})}},
  "light_intensity": {{random.number({"min":0,"max":1200})}},
  "wind_speed": {{random.number({"min":0,"max":45,"precision":0.1})}},
  "battery_level": {{random.number({"min":10,"max":100,"precision":0.1})}}
}
```

### Field reference

| Field | Unit | KDG range |
|-------|------|-----------|
| `temperature` | °C | 12–38 |
| `humidity` | % | 30–95 |
| `soil_moisture` | % | 10–80 |
| `light_intensity` | lux | 0–1200 |
| `wind_speed` | km/h | 0–45 |
| `battery_level` | % | 10–100 |

---

## Frontend

### Tech
- Vanilla JS with ES modules (`type="module"`)
- Chart.js v4 (CDN)
- CSS custom properties for theming
- No build step, no bundler, no authentication

### Layout
- Header: logo left, `LIVE` status indicator right (pulsing green dot)
- Main: responsive CSS grid of chart cards (3 cols → 2 cols → 1 col)
- No sidebar, no navigation, no login, no combobox

### Sensor colors (fixed, used consistently across all charts)

| Sensor | Color |
|--------|-------|
| SENSOR_01 | `#4ade80` green |
| SENSOR_02 | `#38bdf8` blue |
| SENSOR_03 | `#facc15` yellow |
| SENSOR_04 | `#f97316` orange |
| SENSOR_05 | `#fb7185` pink |

### Sensor → Location mapping (hardcoded in `app.js`)

```js
const SENSOR_LOCATIONS = {
  SENSOR_01: 'Fundo Ica Norte - Parcela A3',
  SENSOR_02: 'Fundo Chincha - Parcela B1',
  SENSOR_03: 'Fundo Pisco - Parcela C2',
  SENSOR_04: 'Fundo Ica Sur - Parcela D4',
  SENSOR_05: 'Fundo Chincha - Parcela E1'
};
```

Location is not read from the incoming message — it is resolved from this map by `sensor_id`.

### WebSocket flow (`websocket.js`)
- Reads WebSocket URL from `window.AGRO_CONFIG.wsUrl` (injected by `deploy.sh` into `js/config.js`)
- Connects on page load
- On message: parse JSON, dispatch to chart updaters in `app.js`
- On disconnect: retry with exponential backoff (`Math.min(1000 * 2**attempts, 30000)`, cap 30s)

### Data model in `app.js`

```js
const latestBySensor = {};
// { SENSOR_01: { temperature, humidity, ... }, SENSOR_02: { ... }, ... }
```

On each WebSocket message: store in `latestBySensor[data.sensor_id]`, then update all charts passing all known sensor values. Charts always render all 5 sensors simultaneously.

### Charts (all real-time, 5 series per chart — one per sensor)

| # | Type | Title | Metric | Notes |
|---|------|-------|--------|-------|
| 1 | Line rolling 30pts per sensor | Temperatura | `temperature` | y-axis 0–50°C · segment color per sensor |
| 2 | Bar grouped | Humedad Actual | `humidity` | y-axis 0–100% · 5 bars per update |
| 3 | Line rolling 30pts per sensor | Humedad del Suelo | `soil_moisture` | y-axis 0–100% |
| 4 | Bar grouped | Intensidad Lumínica | `light_intensity` | y-axis 0–1400 lux |
| 5 | Line rolling 30pts per sensor | Velocidad del Viento | `wind_speed` | y-axis 0–60 km/h |
| 6 | Bar horizontal grouped | Nivel de Batería | `battery_level` | x-axis 0–100% · color by level: >50 green · 20–50 yellow · <20 red |

Each chart legend shows `SENSOR_0X — Location Name` so the user knows which line/bar corresponds to which field location.

---

## Deployment

### `deploy.sh`
- Accepts: `--env` (default: `dev`), `--kdg-username`, `--kdg-password`, `--gcp-project`
- Deploys GCP infrastructure first (`infrastructure/gcp/`) via `terraform apply` → captures `function_url`
- Deploys AWS infrastructure (`infrastructure/aws/`) via `terraform apply` passing `gcp_forwarder_url`
- Zips Lambda functions and uploads to deploy S3 bucket
- Generates `frontend/js/config.js`: `window.AGRO_CONFIG = { wsUrl: '...' };`
- Syncs `frontend/` to S3, invalidates CloudFront
- Prints: CloudFront URL, WebSocket URL, KDG URL, BigQuery dataset, Looker Studio link

### `deploy-frontend.sh`
- Frontend-only changes: reads Terraform outputs, regenerates config.js, syncs S3, invalidates CloudFront

### `teardown.sh`
- Requires typed `yes` confirmation
- Empties S3 frontend bucket
- Runs `terraform destroy` on AWS then GCP
- Prints confirmation

---

## Task Breakdown

### Phase 1 — GCP Infrastructure
- [ ] **GCP-01** Create `infrastructure/gcp/main.tf` — provider, backend config
- [ ] **GCP-02** Create `infrastructure/gcp/pubsub.tf` — topic + push subscription
- [ ] **GCP-03** Create `infrastructure/gcp/bigquery.tf` — dataset + partitioned table
- [ ] **GCP-04** Create `infrastructure/gcp/functions.tf` — Cloud Function telemetry-ingest
- [ ] **GCP-05** Create `gcp-functions/telemetry-ingest/index.js` — Pub/Sub → BigQuery

### Phase 2 — AWS Infrastructure
- [ ] **AWS-01** Create `infrastructure/aws/main.tf` — provider, backend config
- [ ] **AWS-02** Create `infrastructure/aws/kinesis.tf`
- [ ] **AWS-03** Create `infrastructure/aws/dynamodb.tf`
- [ ] **AWS-04** Create `infrastructure/aws/cognito.tf` — wraps KDG CloudFormation via Terraform
- [ ] **AWS-05** Create `infrastructure/aws/iam.tf` — roles for all three Lambdas
- [ ] **AWS-06** Create `infrastructure/aws/s3.tf`
- [ ] **AWS-07** Create `infrastructure/aws/cloudfront.tf`
- [ ] **AWS-08** Create `infrastructure/aws/compute.tf` — ws-handler + data-processor + gcp-forwarder + API GW WS

### Phase 3 — Lambda Functions
- [ ] **LAMBDA-01** Implement `app/lambdas/data-processor/index.mjs` — decode Kinesis, write DynamoDB, broadcast WS, invoke gcp-forwarder async
- [ ] **LAMBDA-02** Implement `app/lambdas/ws-handler/index.mjs` — $connect/$disconnect
- [ ] **LAMBDA-03** Implement `app/lambdas/gcp-forwarder/index.mjs` — POST to GCP Pub/Sub REST API

### Phase 4 — Frontend
- [ ] **FE-01** Create `frontend/index.html`
- [ ] **FE-02** Create `frontend/css/styles.css` — dark theme, CSS grid
- [ ] **FE-03** Create `frontend/js/charts.js` — 6 Chart.js instances with thresholds
- [ ] **FE-04** Create `frontend/js/websocket.js` — connect, dispatch, exponential backoff
- [ ] **FE-05** Create `frontend/js/app.js` — entry point
- [ ] **FE-06** Create `frontend/assets/logo.svg` — AgroAndina logo

### Phase 5 — Deployment Scripts
- [ ] **DEPLOY-01** Create `deploy.sh` — GCP first, then AWS, generate config.js, sync frontend
- [ ] **DEPLOY-02** Create `deploy-frontend.sh`
- [ ] **DEPLOY-03** Create `teardown.sh`
- [ ] **DEPLOY-04** Create `kdg-template.json`

### Phase 6 — Validation
- [ ] **DEMO-01** Deploy from scratch, confirm KDG sends data
- [ ] **DEMO-02** Confirm WebSocket dashboard updates in real time
- [ ] **DEMO-03** Confirm records appear in BigQuery
- [ ] **DEMO-04** Confirm Looker Studio reflects data

---

## Non-goals (explicitly out of scope)

- No custom domain or ACM/GCP certificate
- No unit or integration tests
- No server-side rendering
- No mobile-specific layout
- No real sensor API integration
- No frontend authentication
- No GCP authentication on Pub/Sub endpoint (token via env var)
- No circuit breaker or retry in gcp-forwarder (fire and forget)
- No Vertex AI / ML models
- No Dataflow (Cloud Functions sufficient for demo volume)
