# AgroAndina Monitor

**Curso:** Programación Multi-Nube  
**Equipo:** Grupo 1  
**Integrantes:** <!-- Agregar nombres -->  
**Institución:** UTEC  

Dashboard IoT en tiempo real para AgroAndina Fresh S.A.C., empresa agroindustrial con fundos en Ica y Chincha. El sistema permite monitorear en tiempo real variables ambientales críticas (temperatura, humedad, humedad del suelo, intensidad lumínica, velocidad del viento y nivel de batería) desde 5 sensores distribuidos en campo, con analítica histórica en GCP.

---

## Índice

1. [Problema y objetivos](#1-problema-y-objetivos)
2. [Requerimientos](#2-requerimientos)
3. [Arquitectura](#3-arquitectura)
4. [Principios y patrones aplicados](#4-principios-y-patrones-aplicados)
5. [Decisiones de arquitectura](#5-decisiones-de-arquitectura)
6. [Seguridad](#6-seguridad)
7. [Costos estimados](#7-costos-estimados)
8. [Estructura del proyecto](#8-estructura-del-proyecto)
9. [Guía de despliegue](#9-guía-de-despliegue)
10. [Generación de datos de prueba](#10-generación-de-datos-de-prueba)
11. [Analítica histórica con Looker Studio](#11-analítica-histórica-con-looker-studio)
12. [Monitoreo y alertas](#12-monitoreo-y-alertas)
13. [Limitaciones y trabajo futuro](#13-limitaciones-y-trabajo-futuro)
14. [Capturas de pantalla](#14-capturas-de-pantalla)
15. [Destruir infraestructura](#15-destruir-infraestructura)

---

## 1. Problema y objetivos

### Contexto

AgroAndina Fresh S.A.C. opera múltiples fundos agrícolas en la costa peruana. Las condiciones ambientales (temperatura, humedad, radiación solar, viento) afectan directamente la calidad de los cultivos. Actualmente el monitoreo se realiza de forma manual, lo que genera retrasos en la detección de condiciones adversas.

### Problema

No existe visibilidad en tiempo real del estado ambiental de los fundos. Los problemas (heladas, exceso de humedad, fallas de batería en sensores) se detectan horas después de ocurrir, cuando el daño ya es irreversible.

### Objetivos

- Ingestar lecturas de sensores IoT en tiempo real desde múltiples puntos de campo
- Visualizar los 5 sensores simultáneamente en un dashboard web con actualización automática
- Almacenar el historial de lecturas para análisis retrospectivo
- Implementar la solución con arquitectura multi-cloud usando infraestructura como código (Terraform)
- Proteger el acceso al dashboard mediante autenticación con email y verificación de cuenta

### Sensores y ubicaciones

| Sensor | Ubicación |
|--------|-----------|
| SENSOR_01 | Fundo Ica Norte — Parcela A3 |
| SENSOR_02 | Fundo Chincha — Parcela B1 |
| SENSOR_03 | Fundo Pisco — Parcela C2 |
| SENSOR_04 | Fundo Ica Sur — Parcela D4 |
| SENSOR_05 | Fundo Chincha — Parcela E1 |

---

## 2. Requerimientos

### Funcionales

| ID | Requerimiento |
|----|---------------|
| RF-01 | El sistema debe ingestar lecturas de sensores IoT en tiempo real desde 5 puntos de campo simultáneamente |
| RF-02 | El dashboard debe mostrar los 6 indicadores (temperatura, humedad, humedad del suelo, intensidad lumínica, velocidad del viento, batería) actualizados en tiempo real sin necesidad de refrescar la página |
| RF-03 | El dashboard debe mostrar los datos de los 5 sensores de forma simultánea en el mismo gráfico por indicador |
| RF-04 | El sistema debe almacenar el historial completo de lecturas para consultas analíticas retrospectivas |
| RF-05 | El acceso al dashboard debe estar protegido por autenticación con usuario y contraseña |
| RF-06 | Los usuarios deben poder crear su propia cuenta con verificación de identidad por email |
| RF-07 | El sistema debe reenviar cada lectura de sensor a GCP para su almacenamiento analítico en BigQuery |
| RF-08 | El sistema debe notificar por email cuando la integración con GCP presenta errores |
| RF-09 | El historial almacenado en BigQuery debe ser consultable mediante una herramienta de visualización (Looker Studio) |
| RF-10 | Toda la infraestructura debe poder desplegarse y destruirse de forma automatizada |

### No Funcionales

| ID | Categoría | Requerimiento |
|----|-----------|---------------|
| RNF-01 | **Latencia** | El tiempo entre la lectura del sensor y la actualización del dashboard no debe superar los 5 segundos en condiciones normales |
| RNF-02 | **Disponibilidad** | Los componentes de ingesta y visualización deben aprovechar la alta disponibilidad nativa de los servicios serverless (Lambda, API Gateway, CloudFront) sin configuración adicional |
| RNF-03 | **Escalabilidad** | La arquitectura serverless debe escalar automáticamente ante picos de carga sin intervención manual |
| RNF-04 | **Seguridad** | Las credenciales de acceso entre nubes deben almacenarse cifradas y nunca exponerse en código fuente ni logs |
| RNF-05 | **Seguridad** | Cada componente debe operar con permisos mínimos (principio de least privilege) mediante roles IAM individuales |
| RNF-06 | **Trazabilidad** | Toda la infraestructura debe estar etiquetada con tags consistentes para identificación, auditoría y control de costos |
| RNF-07 | **Reproducibilidad** | El entorno completo debe poder recrearse desde cero con un único comando de despliegue, sin pasos manuales intermedios |
| RNF-08 | **Resiliencia** | Los mensajes de telemetría no deben perderse ante fallos temporales de la Cloud Function: Pub/Sub debe reintentar la entrega automáticamente |
| RNF-09 | **Desacoplamiento** | Los componentes de procesamiento no deben conocerse entre sí directamente; la comunicación debe realizarse a través de buses de eventos o colas de mensajes |
| RNF-10 | **Observabilidad** | Los errores críticos en la integración cross-cloud deben generar alertas activas, no solo logs pasivos |

---

## 3. Arquitectura

### Diagrama

```
KDG (simulador de sensores IoT)
    │  Kinesis Data Stream
    ▼
data-processor (Lambda Node.js 24)
    ├── DynamoDB (historial con TTL 3h)
    ├── API Gateway WebSocket ──────────────────► Dashboard web (tiempo real)
    └── EventBridge custom bus
              │  Rule: source = angroandina.telemetry
              ▼
        gcp-forwarder (Lambda Node.js 24)
              │  OAuth2 Bearer token
              │  (SA key desde Secrets Manager)
              ▼
         GCP Pub/Sub topic
              │  Push subscription
              ▼
     Cloud Function telemetry-ingest (Node.js 22)
              │
           BigQuery ◄──────────────────────────── Looker Studio (analítica histórica)

Frontend: S3 + CloudFront
Auth:     Amazon Cognito (auto-registro con verificación por email)
IaC:      Terraform (remote state en S3 + DynamoDB para AWS, GCS para GCP)
CI/CD:    GitHub Actions
Alertas:  CloudWatch Alarm → SNS → email (errores en gcp-forwarder)
```

### Servicios por nube

**AWS**
| Servicio | Rol |
|----------|-----|
| Kinesis Data Streams | Ingesta de telemetría en tiempo real |
| Lambda (×3) | Procesamiento, WebSocket, reenvío a GCP |
| DynamoDB (×2) | Historial de telemetría y conexiones WebSocket |
| API Gateway WebSocket | Canal de push al dashboard |
| EventBridge | Bus de eventos desacoplado entre Lambdas |
| Secrets Manager | Almacenamiento seguro de SA key de GCP |
| S3 + CloudFront | Hosting del frontend con CDN global |
| Cognito | Autenticación con auto-registro y verificación por email |
| CloudFormation | Deploy del Kinesis Data Generator |
| CloudWatch Alarms | Monitoreo de errores en gcp-forwarder |
| SNS | Notificaciones por email ante errores |

**GCP**
| Servicio | Rol |
|----------|-----|
| Pub/Sub | Cola de mensajes entre AWS y la Cloud Function |
| Cloud Functions Gen2 | Recibe push de Pub/Sub y escribe en BigQuery |
| BigQuery | Almacén analítico de historial de telemetría |
| Cloud Storage | Fuente de código para Cloud Functions |
| Looker Studio | Visualización histórica (SaaS, sin IaC) |

---

## 4. Principios y patrones aplicados

### Infraestructura como Código (IaC)

Toda la infraestructura —en ambas nubes— se define en archivos Terraform versionados en el repositorio. No existe ningún recurso creado manualmente (salvo el remote state inicial, creado por `bootstrap-state.sh`). Esto garantiza:

- **Reproducibilidad:** cualquier integrante puede destruir y recrear el entorno completo con un `git push`
- **Auditoría:** cada cambio de infraestructura queda registrado en git con autor y fecha
- **Consistencia:** los mismos tags/labels se aplican a todos los recursos en ambas nubes mediante `locals`

El estado de Terraform se almacena de forma remota y con bloqueo para evitar conflictos:
- AWS: S3 (versionado + cifrado) + DynamoDB (lock)
- GCP: Cloud Storage bucket

### CI/CD con GitHub Actions

El pipeline automatiza el ciclo completo de despliegue en un solo push a `main`:

```
push → GCP apply → store SA key en Secrets Manager → AWS apply → S3 sync → CloudFront invalidation
```

- **Cero intervención manual** después del bootstrap inicial
- **Orden garantizado:** GCP se despliega primero — el topic de Pub/Sub debe existir antes de que AWS configure la Lambda
- **Secretos seguros:** las credenciales nunca tocan el disco — viven en GitHub Secrets y se pasan como variables de entorno efímeras al runner

### Arquitectura Event-Driven

El sistema está diseñado alrededor de eventos, no de llamadas directas entre componentes:

| Productor | Mecanismo | Consumidor |
|-----------|-----------|------------|
| KDG (sensores) | Kinesis Data Stream | `data-processor` Lambda |
| `data-processor` | EventBridge custom bus (`SensorReading`) | `gcp-forwarder` Lambda |
| `gcp-forwarder` | GCP Pub/Sub topic (publish REST API) | Pub/Sub push subscription |
| Pub/Sub push subscription | HTTP push a Cloud Function | `telemetry-ingest` → BigQuery |
| `data-processor` | API Gateway WebSocket | Dashboard web |
| CloudWatch Alarm | SNS topic | Email |

Ningún productor conoce a su consumidor. Esto permite agregar nuevos consumidores (alertas, auditoría, nuevas nubes) sin modificar el código existente. El patrón se aplica tanto dentro de AWS (Kinesis → EventBridge) como entre nubes (Pub/Sub → Cloud Function).

### Microservicios Serverless

Cada unidad de cómputo tiene una única responsabilidad y se despliega de forma independiente:

| Servicio | Nube | Responsabilidad única |
|----------|------|-----------------------|
| `ws-handler` Lambda | AWS | Gestionar el ciclo de vida de conexiones WebSocket |
| `data-processor` Lambda | AWS | Procesar el stream de Kinesis y distribuir el evento |
| `gcp-forwarder` Lambda | AWS | Autenticar contra GCP y publicar en Pub/Sub |
| `telemetry-ingest` Cloud Function | GCP | Recibir el push de Pub/Sub y escribir en BigQuery |

Cada uno tiene su propio rol IAM con permisos mínimos (principio de least privilege), su propio timeout calibrado a su carga, y puede escalar, fallar o actualizarse de forma independiente. No comparten estado en memoria ni acceden a los recursos de los demás.

### Multi-Cloud

La elección de servicios sigue el principio de usar el mejor servicio de cada proveedor para cada necesidad:

| Necesidad | Servicio | Nube | Justificación |
|-----------|----------|------|---------------|
| Ingesta IoT de alta velocidad | Kinesis Data Streams | AWS | Estándar de industria para streaming IoT |
| Cómputo serverless | Lambda | AWS | Ecosistema maduro, integración nativa con Kinesis |
| Bus de eventos interno | EventBridge | AWS | Desacoplamiento nativo entre servicios AWS |
| Autenticación | Cognito | AWS | Gestión de usuarios sin servidor propio |
| Mensajería asíncrona cross-cloud | Pub/Sub | GCP | Garantía de entrega con retry automático |
| Analítica a escala | BigQuery | GCP | Motor columnar optimizado para consultas OLAP |
| Visualización histórica | Looker Studio | GCP | Integración nativa con BigQuery sin infraestructura adicional |

La comunicación entre nubes se realiza de forma segura: la Lambda obtiene un OAuth2 token generado con una Service Account key almacenada en AWS Secrets Manager, sin exponer credenciales en el código.

---

## 5. Decisiones de Arquitectura

### ¿Por qué multi-cloud?

AWS es la nube líder en servicios de ingesta IoT (Kinesis) y cómputo serverless con bajo costo de entrada. GCP tiene ventaja competitiva en analítica a escala con BigQuery y su integración nativa con Looker Studio. La combinación permite usar el mejor servicio de cada proveedor sin quedar atado a uno solo.

### ¿Por qué EventBridge entre data-processor y gcp-forwarder?

Sin EventBridge, `data-processor` invocaría directamente a `gcp-forwarder` — un acoplamiento fuerte donde una Lambda conoce y depende de otra. Con EventBridge:

- `data-processor` solo publica un evento al bus; no sabe quién lo consume
- Se pueden agregar más consumidores (alertas, logs, auditoría) sin modificar `data-processor`
- Si `gcp-forwarder` falla, el bus puede reintentar de forma independiente

### ¿Por qué Pub/Sub en GCP en vez de llamar directo a la Cloud Function?

Llamar directamente a la Cloud Function desde Lambda crea acoplamiento sincrónico cross-cloud: si GCP tiene latencia, la Lambda espera (o falla). Con Pub/Sub:

- El mensaje queda en la cola aunque la Cloud Function esté momentáneamente caída
- Pub/Sub reintenta automáticamente con backoff (10s–60s) hasta que la función responde
- Se pueden agregar otros suscriptores al topic en el futuro sin cambiar AWS

### ¿Por qué DynamoDB con TTL para el historial en tiempo real?

DynamoDB sirve como buffer de estado actual para el WebSocket: cuando un cliente se conecta puede ver el último valor de cada sensor inmediatamente. El TTL de 3 horas evita acumulación ilimitada de datos — el historial permanente vive en BigQuery.

### ¿Por qué Cognito con auto-registro?

En vez de que un administrador cree cada usuario manualmente, Cognito permite auto-registro con verificación de email. El usuario crea su cuenta, recibe un código de 6 dígitos y queda habilitado sin intervención del equipo.

---

## 4. Seguridad

### Autenticación de usuarios

- El dashboard está protegido por Amazon Cognito con flujo `USER_PASSWORD_AUTH`
- Los tokens (ID, Access, Refresh) se almacenan en `sessionStorage` — no persisten si se cierra el navegador
- Las contraseñas requieren mínimo 8 caracteres, mayúscula, minúscula y número (política Cognito)
- El auto-registro incluye verificación de email antes de activar la cuenta

### Autenticación AWS → GCP

La Lambda `gcp-forwarder` necesita publicar en Pub/Sub (API de GCP). El flujo de autenticación es:

1. La SA key JSON de GCP se almacena cifrada en **AWS Secrets Manager**
2. En cada invocación (o cuando el token expira), la Lambda recupera la key, genera un JWT firmado con RS256 y lo intercambia por un OAuth2 Bearer token en `oauth2.googleapis.com`
3. El token se cachea en el scope del módulo (warm invocations lo reutilizan)
4. Pub/Sub valida el token antes de aceptar la publicación

### Recursos públicos vs privados

| Recurso | Acceso | Justificación |
|---------|--------|---------------|
| CloudFront / S3 | Público | Es el frontend web |
| API Gateway WebSocket | Público con token Cognito | El token se valida en cada conexión |
| Cloud Function telemetry-ingest | Público | Restricción de permisos del entorno (ver Limitaciones) |
| DynamoDB | Privado (solo Lambdas) | IAM roles por función |
| EventBridge bus | Privado (solo data-processor) | IAM `events:PutEvents` restringido al ARN del bus |
| Secrets Manager | Privado (solo gcp-forwarder) | IAM `secretsmanager:GetSecretValue` restringido al ARN del secret |
| Pub/Sub topic | Privado (autenticado con OAuth2) | Solo el SA puede publicar |

### Infraestructura como código

Todo el stack se define en Terraform. No hay recursos creados manualmente (salvo el remote state, creado por `bootstrap-state.sh`). Esto garantiza reproducibilidad y auditoría de cambios vía git.

---

## 5. Costos estimados

Estimación para el volumen del proyecto (5 sensores, ~1 msg/seg, uso intermitente):

**AWS**

| Servicio | Uso estimado | Costo mensual |
|----------|-------------|---------------|
| Kinesis Data Streams | 1 shard, ~2M registros/mes | ~$0.015 |
| Lambda (3 funciones) | ~2M invocaciones/mes | Free tier |
| DynamoDB | ~2M escrituras, ~1 GB | Free tier |
| API Gateway WebSocket | ~1M mensajes/mes | ~$0.01 |
| EventBridge | ~2M eventos/mes | Free tier (primeros 5M gratis) |
| Secrets Manager | 1 secret | ~$0.40 |
| S3 + CloudFront | < 1 GB transferencia | ~$0.10 |
| Cognito | < 50,000 MAU | Free tier |
| **Total AWS** | | **~$0.53/mes** |

**GCP**

| Servicio | Uso estimado | Costo mensual |
|----------|-------------|---------------|
| Pub/Sub | ~2M mensajes/mes | Free tier (primeros 10 GB) |
| Cloud Functions Gen2 | ~2M invocaciones/mes | Free tier |
| BigQuery | ~1 GB almacenado, ~1 GB consultado | Free tier |
| Cloud Storage | < 1 GB | Free tier |
| **Total GCP** | | **$0.00/mes** |

> Los costos reales en producción escalarían con el volumen de datos. Esta estimación aplica al entorno de desarrollo del proyecto.

---

## 6. Estructura del proyecto

```
.
├── .github/workflows/deploy.yml   # Pipeline CI/CD
├── app/lambdas/
│   ├── ws-handler/                # Maneja conexiones WebSocket (connect/disconnect)
│   ├── data-processor/            # Kinesis → DynamoDB + WebSocket + EventBridge
│   └── gcp-forwarder/             # EventBridge → Pub/Sub (OAuth2 con SA key)
├── frontend/
│   ├── index.html                 # Dashboard principal (6 gráficos, 5 sensores)
│   ├── login.html                 # Login + auto-registro con Cognito
│   ├── css/styles.css
│   └── js/
│       ├── app.js                 # Entry point, leyenda de sensores
│       ├── auth.js                # Autenticación Cognito (vanilla JS, sin SDK)
│       ├── charts.js              # 6 gráficos Chart.js
│       ├── websocket.js           # WebSocket con reconexión exponencial
│       └── config.js              # Generado por pipeline (no en repo)
├── gcp-functions/
│   └── telemetry-ingest/          # Cloud Function: Pub/Sub push → BigQuery
├── infrastructure/
│   ├── aws/                       # Terraform: Kinesis, Lambda, DynamoDB, API GW,
│   │                              #   CloudFront, S3, Cognito, EventBridge, Secrets Manager
│   └── gcp/                       # Terraform: Pub/Sub, Cloud Function, BigQuery
├── bootstrap-state.sh             # Crea backends de Terraform (ejecutar una vez)
├── teardown.sh                    # Destruye toda la infraestructura
└── kdg-template.json              # Template para Kinesis Data Generator
```

### Tags en todos los recursos

| Clave | Valor |
|-------|-------|
| `ProjectName` | `angroandina-monitor` |
| `Environment` | `dev` |
| `ManagedBy` | `terraform` |
| `Owner` | `grupo1-prog-multinube` |

---

## 7. Guía de despliegue

### Prerequisitos locales

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.7
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configurado con credenciales
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`brew install --cask google-cloud-sdk`)
- Node.js 24

### Paso 1 — Configurar GCP

```bash
gcloud init
# Elegir proyecto: utec-posgrado-01
# Región: us-central1

gcloud auth application-default login
gcloud config set project utec-posgrado-01
```

### Paso 2 — Crear Service Account para CI/CD

```bash
PROJECT_ID="utec-posgrado-01"
SA="angroandina-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create angroandina-deployer \
  --display-name "AngroAndina Terraform Deployer"

for role in roles/pubsub.admin roles/bigquery.admin \
            roles/cloudfunctions.admin roles/storage.admin \
            roles/iam.serviceAccountUser roles/run.admin; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA" --role="$role"
done

gcloud iam service-accounts keys create gcp-key.json --iam-account=$SA
```

**No subas `gcp-key.json` al repositorio.**

### Paso 3 — Configurar secrets en GitHub

| Secret | Descripción |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | Access key de AWS |
| `AWS_SECRET_ACCESS_KEY` | Secret key de AWS |
| `GCP_SA_KEY` | Contenido completo de `gcp-key.json` |
| `GCP_PROJECT_ID` | `utec-posgrado-01` |
| `KDG_USERNAME` | Usuario para Kinesis Data Generator |
| `KDG_PASSWORD` | Password para KDG (mín. 8 chars, mayúscula, número) |

### Paso 4 — Bootstrap del remote state (una sola vez)

```bash
export GCP_PROJECT_ID="utec-posgrado-01"
./bootstrap-state.sh
```

Crea los backends de Terraform:
- S3 `angroandina-monitor-tfstate-dev` + DynamoDB `angroandina-tfstate-lock-dev` (AWS)
- GCS `angroandina-monitor-tfstate-dev` (GCP)

### Paso 5 — Deploy

```bash
git push origin main
```

El pipeline despliega en orden: GCP → Secrets Manager → AWS → Frontend.  
Al finalizar, la URL del dashboard aparece en el Job Summary de Actions.

### Paso 6 — Crear usuario

**Auto-registro desde el dashboard:**
1. Abre el dashboard → "Crear cuenta"
2. Ingresa correo y contraseña (mín. 8 chars, mayúscula, número)
3. Verifica el código de 6 dígitos que llega al correo

**O crear usuario administrador:**
```bash
aws cognito-idp admin-create-user \
  --user-pool-id <pool-id> \
  --username tu@email.com \
  --temporary-password "Temp123!" \
  --message-action SUPPRESS
```

---

## 8. Generación de datos de prueba

1. Abre el dashboard primero (para establecer la conexión WebSocket)
2. Accede al KDG con la URL del Job Summary de Actions
3. Credenciales: las definidas en `KDG_USERNAME` / `KDG_PASSWORD`
4. Importa `kdg-template.json` y configura:
   - Stream: `angroandina-monitor-kinesis`
   - Region: `us-east-1`
5. Inicia el envío — los gráficos se actualizan en tiempo real

---

## 9. Analítica histórica con Looker Studio

1. Ir a [lookerstudio.google.com](https://lookerstudio.google.com)
2. Crear reporte → Conectar datos → BigQuery
3. Proyecto: `utec-posgrado-01` → Dataset: `angroandina_monitor_dev` → Tabla: `telemetry`
4. Diseñar gráficos de series de tiempo por sensor y variable

---

## 10. Monitoreo y alertas

Se configuró una alarma de CloudWatch sobre la Lambda `gcp-forwarder` — el punto de integración más crítico del sistema, ya que un fallo aquí detiene el flujo de datos hacia GCP.

| Recurso | Detalle |
|---------|---------|
| SNS topic | `angroandina-monitor-alerts` |
| Suscriptor | `dfloresgonz@gmail.com` (confirmación requerida al primer deploy) |
| Métrica | `AWS/Lambda › Errors › FunctionName=angroandina-monitor-gcp-forwarder` |
| Condición | ≥ 1 error en una ventana de 60 segundos |
| Notifica en | ALARM (error detectado) y OK (recuperación) |

> Al desplegar por primera vez, AWS envía un correo de confirmación a la dirección suscrita. Es necesario aceptarlo para activar las notificaciones.

---

## 13. Limitaciones y trabajo futuro  

### Limitaciones actuales

**Cloud Function pública**  
La Cloud Function `telemetry-ingest` es de acceso público. El diseño original contempla que Pub/Sub la invoque con autenticación OIDC (usando un service account dedicado), lo que la haría privada. Esta mejora no se pudo implementar porque el proyecto de UTEC no otorga el permiso `iam.serviceAccounts.create`. La autenticación entre AWS y GCP sí está resuelta: la Lambda `gcp-forwarder` obtiene un OAuth2 token firmado con la SA key almacenada en Secrets Manager y lo presenta al API de Pub/Sub — el vector público es únicamente el endpoint de la Cloud Function.

**Sin monitoreo exhaustivo**  
Solo se monitorea la Lambda `gcp-forwarder`. En producción se agregarían alertas adicionales por: latencia de WebSocket, fallas de inserción en BigQuery y errores en `data-processor`.

**Datos simulados**  
Los sensores son simulados por el Kinesis Data Generator. En producción real los dispositivos físicos publicarían directamente al stream de Kinesis usando el SDK de AWS IoT o el SDK de Kinesis.

**Single-region**  
Todo AWS está en `us-east-1` y GCP en `us-central1`. En producción se evaluaría desplegar en regiones más cercanas a Perú (`sa-east-1` en AWS, `southamerica-west1` en GCP).

### Trabajo futuro

- Habilitar OIDC en Pub/Sub push cuando el entorno lo permita (hacer Cloud Function privada)
- Ampliar CloudWatch Alarms a `data-processor` y latencia de WebSocket
- Implementar Dead Letter Queue en EventBridge para mensajes no procesados
- Agregar panel de administración para gestionar usuarios de Cognito
- Conectar sensores físicos reales vía AWS IoT Core
- Configurar retención en BigQuery y particionamiento por fecha para optimizar costos de consulta

---

## 14. Capturas de pantalla

### Dashboard en tiempo real

<!-- Insertar captura del dashboard con datos en vivo (6 gráficos, 5 sensores) -->

### Página de login y registro

<!-- Insertar captura del login y del formulario de creación de cuenta -->

### Reporte en Looker Studio

<!-- Insertar captura del reporte histórico conectado a BigQuery -->

### Pipeline de GitHub Actions

<!-- Insertar captura del pipeline exitoso con el Job Summary -->

### Infraestructura en AWS Console

<!-- Insertar captura de los recursos principales (Lambda, DynamoDB, EventBridge) -->

### Infraestructura en GCP Console

<!-- Insertar captura de Cloud Function, Pub/Sub topic y BigQuery tabla -->

---

## 15. Destruir infraestructura

```bash
./teardown.sh
```

Destruye en orden: Terraform destroy (AWS + GCP) → recursos huérfanos → remote state (S3, DynamoDB, GCS).
