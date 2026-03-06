1. What This Project Actually Does (Simple Idea)

You built a cloud platform on Microsoft Azure that:

Runs an application with 3 parts

Runs Apache Airflow workflows

Uses Kubernetes (AKS)

Uses Terraform to create infrastructure

Uses CI/CD pipelines for automation

So the idea is:

👉 Developer writes code → CI builds Docker images → CD deploys to Kubernetes automatically

2. High-Level Flow (Very Simple)

Think of the system like this:

Developer
   |
   | push code
   v
Azure DevOps Pipeline
   |
   | build docker images
   v
Azure Container Registry (ACR)
   |
   | pull images
   v
AKS Kubernetes Cluster
   |
   | run application containers
   v
Users access application


3. Main Components
1️⃣ Terraform (Infrastructure)

Terraform automatically creates Azure resources like:

AKS cluster

Container registry

Network

Storage

Monitoring

Instead of manually creating resources in the portal.

Example resources created:

AKS cluster

ACR

VNet

Storage

Log Analytics

2️⃣ Azure Container Registry (ACR)

This is where Docker images are stored.

Example images:

frontend image
backend image
database image

Flow:

Pipeline builds image
      ↓
Push to ACR
      ↓
AKS pulls image
3️⃣ AKS (Azure Kubernetes Service)

This is where containers actually run.

Inside AKS you created namespaces:

app namespace
airflow namespace
app namespace

Runs the application:

Frontend (React)
Backend (FastAPI)
Database (PostgreSQL)
airflow namespace

Runs Apache Airflow:

Airflow Webserver
Airflow Scheduler
Airflow Workers



4. Application Architecture (3-Tier)

Your application has 3 layers.

User
 |
 v
Frontend (React + Nginx)
 |
 v
Backend (FastAPI API)
 |
 v
Database (PostgreSQL)

Example request flow:

User opens website
        ↓
Frontend calls API
        ↓
Backend processes request
        ↓
Backend queries database
        ↓
Response returned to user


5. CI/CD Pipeline

You created two pipelines.

CI Pipeline (Build)

Runs when code is pushed.

Steps:

1 Build docker images
2 Push images to ACR
3 Validate Helm charts
4 Run terraform plan

Example images built:

frontend
backend
database
CD Pipeline (Deploy)

After CI succeeds:

Deploy to DEV
      ↓
Deploy to STAGE
      ↓
Deploy to PROD (with approval)

Deployment uses:

Helm charts

Command used:

helm upgrade --install


6. Terraform Structure

You organized Terraform nicely using modules.

Structure:

terraform
   |
   |-- modules
   |      networking
   |      acr
   |      aks
   |      storage
   |      monitoring
   |
   |-- environments
          dev
          stage
          prod

Each environment has its own:

terraform state
variables
configuration

This prevents environment conflicts.

7. Security Design

You added several security practices.

Managed Identity

AKS pulls images from ACR without passwords.

AKS → ACR

Using:

AcrPull role
Secrets

Sensitive data stored in:

Kubernetes Secrets

Examples:

database password
database URL
Network Security

Network rules restrict communication:

Frontend → Backend allowed
Backend → Database allowed
Everything else blocked


8. Observability (Monitoring)

You enabled Azure Monitor + Log Analytics.

This collects:

CPU usage
memory usage
container logs
pod metrics

Example alerts:

CPU > 80%
pod restart
high memory


9. Auto Scaling

Your application can scale automatically.

Example:

Frontend pods: 1 → 15
Backend pods: 1 → 20
Airflow workers: 2 → 16

Scaling based on:

CPU usage

Using:

Kubernetes HPA

10. Deployment Steps

To deploy the platform:

Step 1

Create Terraform state storage.

Azure Storage Account
Step 2

Run Terraform.

terraform init
terraform plan
terraform apply

This creates:

AKS
ACR
Network
Monitoring
Step 3

Connect kubectl.

az aks get-credentials
Step 4

Create Kubernetes resources.

namespaces
rbac
secrets
Step 5

Install ingress controller.

NGINX ingress
Step 6

Deploy application.

Using Helm:

database
backend
frontend
Step 7

Deploy Airflow.

helm install airflow