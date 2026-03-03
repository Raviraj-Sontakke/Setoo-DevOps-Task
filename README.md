# Setoo DevOps Platform — Raviraj

Cloud-native platform on Azure: AKS, Terraform, 3-tier app, Apache Airflow, Azure DevOps CI/CD.

## Repository Layout

```
├── terraform/          Infrastructure as Code (modules + environments)
├── docker/             Dockerfiles and application source
│   ├── frontend/       React + Nginx
│   ├── backend/        Python FastAPI
│   └── database/       PostgreSQL + init scripts
├── helm/charts/        Helm charts for all workloads
│   ├── frontend/
│   ├── backend/
│   ├── database/
│   └── airflow/
├── pipelines/          Azure DevOps CI/CD pipeline YAML
│   └── templates/      Reusable pipeline step templates
├── kubernetes/         Namespace and RBAC manifests
└── docs/               Architecture documentation
```

## Quick Start

See [docs/architecture.md](docs/architecture.md) for full deployment instructions.

**To generate the PDF documentation:**
```bash
cd docs
chmod +x generate-pdf.sh
./generate-pdf.sh
```

Requires `pandoc` and a LaTeX engine (`xelatex`). On Ubuntu: `apt install pandoc texlive-xetex`.

## Naming Convention

All Azure resources are prefixed with `raviraj-`:

| Resource | Name |
|---|---|
| Resource Group | raviraj-rg-{env} |
| AKS | raviraj-aks-{env} |
| ACR | ravirajacr{env} |
| Storage | ravirajstorage{env} |
| VNet | raviraj-vnet-{env} |
| Log Analytics | raviraj-logs-{env} |

## Environments

| Environment | AKS Node Count | ACR SKU |
|---|---|---|
| dev | 2 system + 1–5 user | Standard |
| stage | 2 system + 2–8 user | Standard |
| prod | 3 system + 3–10 user | Premium |
