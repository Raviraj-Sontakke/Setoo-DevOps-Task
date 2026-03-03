---
title: "Cloud-Native Platform on Azure — Architecture & Deployment Guide"
author: "Raviraj"
date: "March 2026"
geometry: margin=2.5cm
fontsize: 11pt
toc: true
toc-depth: 3
colorlinks: true
---

\newpage

# 1. Architecture Overview

## 1.1 High-Level Design

The platform is built on Microsoft Azure and follows a cloud-native, container-first approach. The core principle is that every workload runs inside a single AKS cluster, isolated by Kubernetes namespaces, and all infrastructure is provisioned through Terraform.

```
                         ┌─────────────────────────────────────────────────┐
                         │                   Azure                          │
                         │                                                   │
  Developer  ──push──►  │  Azure DevOps                                    │
                         │  ┌──────────┐   ┌──────────┐                    │
                         │  │ CI Pipeline│  │ CD Pipeline│                  │
                         │  └────┬─────┘   └─────┬────┘                    │
                         │       │               │                          │
                         │       ▼               ▼                          │
                         │  ┌─────────────────────────┐                    │
                         │  │  Azure Container Registry│                    │
                         │  │     (ravirajacr)         │                    │
                         │  └───────────┬─────────────┘                    │
                         │              │                                   │
                         │              ▼                                   │
                         │  ┌─────────────────────────────────────────┐    │
                         │  │         AKS Cluster (raviraj-aks)        │    │
                         │  │                                           │    │
                         │  │  ┌─────────────┐  ┌──────────────────┐  │    │
                         │  │  │ Namespace:   │  │  Namespace:       │  │    │
                         │  │  │    app       │  │     airflow       │  │    │
                         │  │  │             │  │                  │  │    │
                         │  │  │ [Frontend]  │  │  [Airflow Web]   │  │    │
                         │  │  │ [Backend]   │  │  [Scheduler]     │  │    │
                         │  │  │ [PostgreSQL]│  │  [Workers]       │  │    │
                         │  │  └─────────────┘  └──────────────────┘  │    │
                         │  └─────────────────────────────────────────┘    │
                         │                                                   │
                         │  ┌────────────────┐  ┌──────────────────────┐   │
                         │  │ Log Analytics  │  │  Storage Account     │   │
                         │  │ (raviraj-logs) │  │  (ravirajstorage)    │   │
                         │  └────────────────┘  └──────────────────────┘   │
                         └─────────────────────────────────────────────────┘
```

## 1.2 Component Summary

| Component | Technology | Azure Resource |
|---|---|---|
| Infrastructure | Terraform | AKS, ACR, VNet, Storage |
| Container Registry | Azure ACR | ravirajacr{env} |
| Kubernetes | AKS 1.30 | raviraj-aks-{env} |
| Frontend | React + Nginx | Deployment in `app` namespace |
| Backend | Python FastAPI | Deployment in `app` namespace |
| Database | PostgreSQL 16 | StatefulSet in `app` namespace |
| Workflow Engine | Apache Airflow 2.10 | Helm release in `airflow` namespace |
| Observability | Azure Monitor + Container Insights | raviraj-logs-{env} |
| CI/CD | Azure DevOps Pipelines | ci.yml / cd.yml |

\newpage

# 2. Infrastructure Design

## 2.1 Terraform Module Structure

The Terraform codebase is split into five reusable modules, each representing a single responsibility:

```
terraform/
├── modules/
│   ├── networking/     VNet, Subnet, NSG, Resource Group
│   ├── acr/            Azure Container Registry + AcrPull role assignment
│   ├── aks/            AKS cluster with system + user node pools
│   ├── storage/        Storage Account for state files and Airflow logs
│   └── monitoring/     Log Analytics Workspace + Container Insights
└── environments/
    ├── dev/
    ├── stage/
    └── prod/
```

Each environment directory (`dev`, `stage`, `prod`) contains:

- `providers.tf` — Terraform version constraints, AzureRM provider, and the remote backend pointing to the correct state key.
- `main.tf` — Calls all five modules with environment-specific inputs.
- `variables.tf` — Environment-level overrides (node counts, sizes).
- `outputs.tf` — Exports cluster name, ACR login server, resource group.

## 2.2 Remote State

Terraform state is stored in Azure Blob Storage:

| Attribute | Value |
|---|---|
| Storage Account | ravirajstoragestate |
| Container | tfstate |
| Dev key | dev/terraform.tfstate |
| Stage key | stage/terraform.tfstate |
| Prod key | prod/terraform.tfstate |

State locking is handled natively by Azure Blob Storage using lease-based locking.

## 2.3 AKS Cluster

The AKS cluster uses two node pools:

| Pool | Purpose | VM Size | Scaling |
|---|---|---|---|
| system | kube-system workloads | Standard_D2s_v3 | Fixed (2–3 nodes) |
| user | Application workloads | Standard_D4s_v3 | Auto (1–10 nodes) |

Additional cluster configuration:

- **Networking**: Azure CNI with Azure Network Policy for pod-level traffic control.
- **Identity**: System-assigned managed identity. The kubelet identity is granted `AcrPull` on ACR automatically by the `acr` module.
- **Observability**: OMS Agent is configured to ship node and container metrics to the Log Analytics workspace.
- **Security**: `azure_policy_enabled = true`; node OS disk is 100–128 GB.

\newpage

# 3. Application Architecture

## 3.1 Three-Tier Tasks Application

The application is a simple Task Manager that demonstrates the full request path through the three tiers.

```
Internet
   │
   ▼
NGINX Ingress Controller (NodePort / LoadBalancer)
   │
   ▼
Frontend  (React SPA, served by Nginx on port 80)
   │  /api/* proxied to backend-service:8000
   ▼
Backend   (FastAPI on port 8000)
   │  SQL via asyncpg
   ▼
Database  (PostgreSQL 16, StatefulSet, port 5432)
```

### Frontend

- Built as a multi-stage Docker image: `node:20-alpine` builds the React bundle, `nginx:1.27-alpine` serves it.
- Nginx proxies `/api/` to `backend-service:8000`, enabling the SPA to call the API without CORS issues.
- Stateless — scales horizontally via HPA.

### Backend

- Python 3.12 + FastAPI + `databases` (async PostgreSQL via `asyncpg`).
- Runs as a non-root user (`UID 1000`).
- `DATABASE_URL` is injected from a Kubernetes Secret (`backend-secrets`) so credentials never appear in the image or values files.
- Endpoints: `GET /tasks`, `POST /tasks`, `PATCH /tasks/{id}`, `DELETE /tasks/{id}`, `GET /health`.

### Database

- Custom PostgreSQL image with `init.sql` baked in to create the schema on first start.
- Deployed as a Kubernetes `StatefulSet` with a `VolumeClaimTemplate` backed by `managed-premium` storage class.
- Headless service ensures stable DNS (`database-<release>-0.database-<release>.<namespace>.svc.cluster.local`).
- Credentials sourced from a Kubernetes Secret (`database-secrets`).

## 3.2 Apache Airflow

Airflow is deployed via the **official Apache Airflow Helm chart** (v1.15.0 / Airflow 2.10.3), added as a chart dependency in `helm/charts/airflow/Chart.yaml`.

| Component | Replicas (dev) | Replicas (prod) |
|---|---|---|
| Webserver | 1 | 2 |
| Scheduler | 1 | 2 |
| Celery Workers | 2 (autoscale to 8) | 4 (autoscale to 16) |
| Triggerer | 1 | 1 |

Key configuration choices:

- **Executor**: `CeleryExecutor` with Redis as the broker. This allows workers to scale independently.
- **Persistence**: DAGs and logs use PersistentVolumeClaims (`managed-premium`, 5 Gi and 20 Gi respectively).
- **Bundled PostgreSQL**: The chart's built-in PostgreSQL subchart is used for Airflow's metadata database, keeping it separate from the application database.
- `load_examples: "False"` keeps the UI clean.

\newpage

# 4. CI/CD Pipeline Design

## 4.1 Pipeline Overview

Two Azure DevOps YAML pipelines handle the full software delivery lifecycle:

```
Code push / PR
      │
      ▼
 ┌─────────────────────────────────────┐
 │           CI Pipeline               │
 │                                     │
 │  Stage 1: Build & Push Images       │
 │    - docker build frontend          │
 │    - docker build backend           │
 │    - docker build database          │
 │    - push all to ACR (tag=SHA)      │
 │                                     │
 │  Stage 2: Validate Helm Charts      │
 │    - helm lint all charts           │
 │                                     │
 │  Stage 3: Terraform Plan (on main)  │
 │    - terraform plan dev env         │
 └──────────────┬──────────────────────┘
                │ (triggers CD on main merge)
                ▼
 ┌─────────────────────────────────────┐
 │           CD Pipeline               │
 │                                     │
 │  Stage 1: Deploy to Dev             │
 │    - helm upgrade database          │
 │    - helm upgrade backend           │
 │    - helm upgrade frontend          │
 │    - helm upgrade airflow           │
 │                                     │
 │  Stage 2: Deploy to Stage           │
 │    (requires Dev success)           │
 │                                     │
 │  Stage 3: Deploy to Prod            │
 │    (requires Stage success +        │
 │     environment approval gate)      │
 └─────────────────────────────────────┘
```

## 4.2 Template Reuse

All repetitive steps are extracted into three template files under `pipelines/templates/`:

| Template | Parameters | Purpose |
|---|---|---|
| `build-push.yml` | imageName, dockerfilePath, buildContext, imageTag | Build one image and push to ACR |
| `deploy-helm.yml` | chartPath, releaseName, namespace, valuesFile, overrideValues | `helm upgrade --install` a chart |
| `terraform-apply.yml` | environment, workingDirectory, planOnly | Run init / plan / apply |

## 4.3 Image Tagging Strategy

Every image is tagged with **two tags**:

1. **Git SHA** (`$(Build.SourceVersion)`) — immutable, used in CD to pin exact versions.
2. **`latest`** — convenience tag for local development.

The CD pipeline reads the SHA from the CI pipeline's `sourceCommit` resource variable, ensuring the exact same image that passed CI is deployed to every environment.

## 4.4 Environment Gates

Azure DevOps **Environments** (`dev`, `stage`, `prod`) are used as deployment targets. This enables:

- **Approval gates** on the `prod` environment.
- **Deployment history** and rollback via the Azure DevOps UI.
- **Branch policies** linking deployments to specific branches.

\newpage

# 5. Security Design

## 5.1 Identity and Access

| Concern | Approach |
|---|---|
| AKS → ACR authentication | Managed identity (`kubelet_identity`) with `AcrPull` role; no credentials needed |
| ACR admin account | Disabled (`admin_enabled = false`) |
| Application secrets | Kubernetes Secrets referenced by name; never hardcoded in values files |
| Pod identity | Pods run as non-root users (UID 999 for PostgreSQL, UID 1000 for backend) |
| RBAC | Minimal `Role` + `RoleBinding` per namespace; separate `cicd-sa` ServiceAccount for pipelines |

## 5.2 Network Security

- **NSG**: Allows only TCP 80 and 443 inbound to the AKS subnet.
- **Kubernetes NetworkPolicy**: Default deny-all ingress in the `app` namespace; explicit allow-rules for frontend→backend (port 8000) and backend→database (port 5432).
- **Azure CNI + Azure Network Policy**: Enforced at the vSwitch level, not just by `kube-proxy`.

## 5.3 TLS

- Production ingress resources reference a TLS secret (`app-tls`, `airflow-tls`).
- In a real deployment, these secrets would be populated by **cert-manager** using Let's Encrypt or an internal CA.

\newpage

# 6. Observability

## 6.1 Metrics and Logs

- **Container Insights** is enabled on the AKS cluster via the `oms_agent` block in Terraform. It collects node-level metrics, pod CPU/memory, and container stdout/stderr logs.
- All logs flow to the **Log Analytics Workspace** (`raviraj-logs-{env}`).
- **Azure Monitor Alerts** can be configured on top of this workspace for CPU > 80%, pod restart count, etc.

## 6.2 Application Health

Both the frontend and backend expose a `/health` endpoint used by Kubernetes `livenessProbe` and `readinessProbe`. This ensures that:

- Traffic is only sent to pods that have successfully started.
- Unhealthy pods are automatically restarted.

## 6.3 Autoscaling

**HorizontalPodAutoscaler** (HPA) is configured for frontend and backend:

| Service | Min | Max | CPU Target |
|---|---|---|---|
| Frontend (dev) | 1 | 3 | 70% |
| Frontend (prod) | 3 | 15 | 70% |
| Backend (dev) | 1 | 3 | 70% |
| Backend (prod) | 3 | 20 | 70% |
| Airflow Workers (dev) | 2 | 8 | 70% |
| Airflow Workers (prod) | 4 | 16 | 70% |

The AKS user node pool itself autoscales (1–10 nodes in dev, 3–10 in prod) to accommodate HPA scale-out.

\newpage

# 7. Deployment Instructions

## 7.1 Prerequisites

The following tools must be installed locally:

- `az` CLI (Azure CLI) — authenticated with `az login`
- `terraform` >= 1.6.0
- `kubectl`
- `helm` >= 3.16
- `docker`

Azure prerequisites:

- An Azure Subscription with Contributor rights
- A Service Principal (or Workload Identity Federation) for Azure DevOps pipelines
- Azure DevOps organization and project

## 7.2 Step 1 — Bootstrap Remote State Storage

This is a one-time manual step to create the storage account that holds Terraform state.

```bash
az group create --name raviraj-rg-shared --location eastus

az storage account create \
  --name ravirajstoragestate \
  --resource-group raviraj-rg-shared \
  --sku Standard_LRS \
  --min-tls-version TLS1_2

az storage container create \
  --name tfstate \
  --account-name ravirajstoragestate
```

## 7.3 Step 2 — Provision Infrastructure

```bash
cd terraform/environments/dev

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Repeat for `stage` and `prod` as needed.

After apply, capture outputs:

```bash
export AKS_NAME=$(terraform output -raw aks_cluster_name)
export ACR_SERVER=$(terraform output -raw acr_login_server)
export RESOURCE_GROUP=$(terraform output -raw resource_group_name)
```

## 7.4 Step 3 — Configure kubectl

```bash
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_NAME \
  --overwrite-existing
```

## 7.5 Step 4 — Create Kubernetes Namespaces and RBAC

```bash
kubectl apply -f kubernetes/namespaces.yaml
kubectl apply -f kubernetes/rbac.yaml
```

## 7.6 Step 5 — Create Application Secrets

```bash
kubectl create secret generic database-secrets \
  --namespace app \
  --from-literal=postgres-user=postgres \
  --from-literal=postgres-password=<STRONG_PASSWORD>

kubectl create secret generic backend-secrets \
  --namespace app \
  --from-literal=database-url="postgresql://postgres:<STRONG_PASSWORD>@database-database-0.database-database.app.svc.cluster.local:5432/tasks"
```

## 7.7 Step 6 — Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2
```

## 7.8 Step 7 — Deploy the 3-Tier Application

```bash
# Database
helm upgrade --install database helm/charts/database \
  --namespace app \
  --values helm/charts/database/values.yaml \
  --set image.repository=$ACR_SERVER/database \
  --atomic

# Backend
helm upgrade --install backend helm/charts/backend \
  --namespace app \
  --values helm/charts/backend/values-dev.yaml \
  --set image.repository=$ACR_SERVER/backend \
  --set image.tag=<GIT_SHA> \
  --atomic

# Frontend
helm upgrade --install frontend helm/charts/frontend \
  --namespace app \
  --values helm/charts/frontend/values-dev.yaml \
  --set image.repository=$ACR_SERVER/frontend \
  --set image.tag=<GIT_SHA> \
  --atomic
```

## 7.9 Step 8 — Deploy Apache Airflow

```bash
helm repo add apache-airflow https://airflow.apache.org
helm repo update

cd helm/charts/airflow
helm dependency update

helm upgrade --install airflow . \
  --namespace airflow \
  --values values.yaml \
  --atomic \
  --timeout 15m
```

## 7.10 Step 9 — Set Up Azure DevOps Pipelines

1. In Azure DevOps, create the following **Service Connections**:
   - `raviraj-azure-connection` — Azure Resource Manager connection to your subscription.
   - `raviraj-acr-connection` — Docker Registry connection to ACR.
   - `raviraj-aks-connection` — Kubernetes Service Connection to AKS.

2. Create **Environments** named `dev`, `stage`, and `prod`. Add an approval gate on `prod`.

3. Import the CI pipeline from `pipelines/ci.yml` and name it `raviraj-ci`.

4. Import the CD pipeline from `pipelines/cd.yml` and name it `raviraj-cd`.

5. Trigger the CI pipeline by pushing any code change.

## 7.11 Rollback

To roll back an application to a previous Helm release:

```bash
helm history frontend -n app
helm rollback frontend <REVISION> -n app
```

For infrastructure rollback, restore a previous Terraform state:

```bash
az storage blob list \
  --container-name tfstate \
  --account-name ravirajstoragestate \
  --prefix dev/

az storage blob restore ...
```

\newpage

# 8. Key Design Decisions

## 8.1 Single Cluster, Multiple Namespaces

Rather than separate clusters per environment, a single AKS cluster with namespace-level isolation was chosen for dev and stage workloads. Production runs on its own dedicated cluster. This reduces cost while maintaining isolation via Kubernetes RBAC and NetworkPolicy.

## 8.2 Terraform Modules Over Workspaces

Terraform workspaces were considered but modules with separate environment directories were preferred. This provides:

- Independent state files per environment (no accidental cross-env apply).
- The ability to have different provider versions or backend configs per environment.
- Clearer blast-radius scoping.

## 8.3 Helm for Application Delivery

Helm was chosen over raw Kubernetes YAML for application deployment because:

- Environment-specific values files (`values-dev.yaml`, `values-prod.yaml`) avoid duplication.
- `helm upgrade --install --atomic` gives idempotent, rollback-safe deployments.
- The Airflow community chart (30k+ stars) provides a battle-tested baseline.

## 8.4 CeleryExecutor for Airflow

`CeleryExecutor` with Redis was chosen over `KubernetesExecutor` to allow predictable, persistent worker pods with autoscaling. `KubernetesExecutor` would provide better isolation per task but introduces higher scheduling latency, which is unnecessary for this deployment.

## 8.5 Managed Identity Over Service Principals

AKS uses a system-assigned managed identity, and the kubelet identity pulls images from ACR without any stored credential. This eliminates credential rotation concerns and reduces the secret management surface.

\newpage

# 9. Assumptions

1. The Azure subscription has sufficient quota for the required VM sizes (`Standard_D2s_v3`, `Standard_D4s_v3`).
2. The `eastus` region is acceptable. The `location` variable can override this per environment.
3. DNS and TLS certificate provisioning (cert-manager / Let's Encrypt) are out of scope. TLS secret names are referenced but the creation is documented as a manual step or a separate cert-manager deployment.
4. The CI/CD pipelines assume self-hosted or Microsoft-hosted Ubuntu agents with Docker, kubectl, and Helm pre-installed (or installed via pipeline tasks).
5. For local development, `docker compose` with the three service images is assumed but not configured in this repository (out of scope).
6. The Apache Airflow Helm chart version `1.15.0` ships Airflow `2.10.3`. Future updates should align `appVersion` in `Chart.yaml`.
7. The PostgreSQL StatefulSet runs a single replica (no high-availability). For production, Azure Database for PostgreSQL Flexible Server would be a better choice.

\newpage

# 10. Optional Enhancements

## 10.1 Monitoring and Alerting

- Deploy **Prometheus + Grafana** via the `kube-prometheus-stack` Helm chart for application-level metrics.
- Add `ServiceMonitor` resources to scrape FastAPI `/metrics` endpoint.
- Configure alert rules for request latency, error rate, and pod restarts.

## 10.2 Security Enhancements

- Replace Kubernetes Secrets with **Azure Key Vault** + CSI Secrets Store Driver for zero-secret-in-cluster storage.
- Enable **Defender for Containers** on the AKS cluster.
- Add **OPA Gatekeeper** / **Azure Policy** constraints to enforce runAsNonRoot and disallow privileged pods cluster-wide.

## 10.3 Cost Optimisation

- Use **spot node pools** for Airflow workers (tolerate eviction) to reduce cost by 60–80%.
- Enable **cluster stop** for dev/stage environments during off-hours.
- Use ACR `Basic` SKU in dev and `Standard` in stage; reserve `Premium` for prod (geo-replication).

## 10.4 GitOps with Flux or Argo CD

Replace the CD pipeline's `helm upgrade` steps with a GitOps controller (Argo CD or Flux). The pipeline would push updated values to a config repository; the controller would reconcile the cluster state continuously.
