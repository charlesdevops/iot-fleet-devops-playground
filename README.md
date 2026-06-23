# Fleet Registry — Edge Device & Firmware Service

A production-ready Python API for registering edge/IoT devices and storing their
firmware/config blobs. Demonstrates Docker, Terraform IaC, Kubernetes/Helm deployment,
GitHub Actions CI/CD, and a built-in observability stack.

> **Disclaimer:** This repository was built with the assistance of [Claude Code](https://claude.ai/code) (Anthropic's AI coding tool). All generated code, configuration, and documentation has been reviewed and manually verified end-to-end by the author.

---

## Architecture

```
┌──────────────┐   POST /devices       ┌──────────────┐
│   Client     │ ─────────────────────▶│  FastAPI     │
│              │ ◀─────────────────────│  (uvicorn)   │
│              │   GET /devices         └──────┬───────┘
└──────────────┘                              │
                                    ┌─────────┴──────────┐
                                    │                    │
                               ┌────▼─────┐        ┌─────▼─────┐
                               │ DynamoDB │        │    S3     │
                               │(devices) │        │(firmware) │
                               └──────────┘        └───────────┘
```

**Stack**

| Layer         | Technology                            |
| ------------- | ------------------------------------- |
| API           | Python 3.12 · FastAPI · uvicorn      |
| Persistence   | AWS DynamoDB (PAY\_PER\_REQUEST)      |
| Object store  | AWS S3 (SSE-KMS CMK, versioned)       |
| Encryption    | AWS KMS (CMK, automatic key rotation) |
| Observability | Prometheus `/metrics` · JSON logs · Grafana |
| IaC           | Terraform ≥ 1.5 (hashicorp/aws)      |
| Container     | Docker multi-stage, non-root user     |
| Orchestration | Kubernetes · Helm 3                  |
| Auth (K8s)    | IRSA (IAM Roles for Service Accounts) |
| CI/CD         | GitHub Actions                        |
| Local AWS     | LocalStack CE                         |

---

## Prerequisites

| Tool             | Version |
| ---------------- | ------- |
| Python           | ≥ 3.12 |
| Poetry           | ≥ 1.8  |
| Docker + Compose | ≥ 24   |
| Terraform        | ≥ 1.5  |
| Helm             | ≥ 3.14 |
| kubectl          | any     |
| minikube         | any     |
| AWS CLI          | any     |

On Ubuntu (native or WSL2) all prerequisites can be installed automatically:

```bash
bash setup.sh
```

---

## Quick Start (LocalStack)

### 0. Install system dependencies

```bash
bash setup.sh
```

> Skip this step if all tools are already installed.

### 1. Install Python dependencies

```bash
make install
```

### 2. Run unit tests

```bash
make test
```

### 3. Start LocalStack + app

```bash
make up
```

### 4. Provision AWS resources in LocalStack

```bash
make infra-init   # first time only
make infra-apply
```

> The Terraform state is stored locally. For production, configure an S3 backend.

### 5. Smoke-test the stack

```bash
make smoke
```

This runs five sequential checks — health, register device, list devices, DynamoDB scan,
S3 objects — and prints a pass/fail summary table. The script is at
[scripts/smoke.sh](scripts/smoke.sh) and can also be called directly:
`scripts/smoke.sh <app-url> [localstack-url]`.

### 6. Stop everything

```bash
make down
make infra-destroy
```

---

## Quick Start (minikube)

Requires LocalStack already running (`make up && make infra-apply`).

```bash
make minikube-up     # start minikube + build image + deploy chart
make minikube-smoke  # smoke-test the app running inside the cluster
```

Individual targets:

```bash
make minikube-start  # start minikube only
make minikube-build  # build the image inside minikube's Docker daemon
make minikube-deploy # install/upgrade the Helm chart
make minikube-delete # remove the Helm release
make minikube-stop   # stop minikube
```

The local chart override ([helm/fleet-api/values-local.yaml](helm/fleet-api/values-local.yaml))
sets `imagePullPolicy: Never`, `NodePort` service, single replica, and routes AWS calls to
`host.minikube.internal:4566` (LocalStack on the host).

---

## Components

### Python API

FastAPI app with automatic OpenAPI docs at `/docs`:

| Method | Path        | Description                                    |
| ------ | ----------- | ---------------------------------------------- |
| GET    | /devices    | Scan DynamoDB, return all registered devices   |
| POST   | /devices    | Upload firmware to S3, write device to DynamoDB |
| GET    | /healthz    | Liveness/readiness probe target                |
| GET    | /metrics    | Prometheus metrics                             |
| GET    | /docs       | Swagger UI (OpenAPI)                           |

Configuration is read from environment variables (see [app/.env-example](app/.env-example))
via `pydantic-settings`.

### Docker

Multi-stage build: the builder stage installs Poetry and exports a plain
`requirements.txt`; the runtime stage copies only the requirements and application source —
Poetry is not present in the final image. The container runs as a non-root user (`uid 1000`)
enforced via `USER` in the Dockerfile, with `gunicorn` (uvicorn worker class) serving the
ASGI app on port 8000.

### Terraform IaC

Resources created:

- **DynamoDB table** `devices-{environment}` — `device_id` as hash key, PAY\_PER\_REQUEST billing, PITR enabled
- **S3 bucket** `fleet-firmware-{environment}` — versioning, SSE-KMS with CMK, public access blocked, bucket key enabled
- **KMS key** `fleet-api-s3-cmk-{environment}` — CMK for S3 encryption, automatic annual key rotation
- **IAM role** `fleet-api-role-{environment}` — least-privilege policy (DynamoDB Scan/PutItem/GetItem, S3 PutObject/GetObject, KMS GenerateDataKey/Decrypt)

The IAM role uses an **IRSA trust policy** when `eks_oidc_provider_arn` and
`eks_oidc_provider_url` variables are set, allowing Kubernetes pods to authenticate via OIDC
without static credentials. When those variables are empty, it falls back to an EC2 trust
policy for local testing.

To target LocalStack instead of real AWS:

```bash
terraform apply -var="localstack_endpoint=http://localhost:4566"
```

### Helm Chart

Key reliability features:

| Feature              | Implementation                                          |
| -------------------- | ------------------------------------------------------- |
| Liveness probe       | `GET /healthz` — restarts stuck pods                 |
| Readiness probe      | `GET /healthz` — removes unhealthy pods from Service |
| Autoscaling          | HPA: 2–10 replicas, CPU target 70%                     |
| Non-root container   | `securityContext.runAsNonRoot: true`                  |
| Read-only filesystem | `readOnlyRootFilesystem: true`                        |
| IRSA                 | ServiceAccount annotated with IAM role ARN              |
| Config separation    | Non-sensitive config in ConfigMap; secrets via IRSA     |
| Metrics scraping     | Optional Prometheus-Operator `ServiceMonitor`         |
| Dashboards           | Optional Grafana dashboard ConfigMap (sidecar import)   |

### Observability

- **Metrics:** `prometheus-fastapi-instrumentator` exposes request rate, latency, and
  in-progress counts at `GET /metrics`.
- **Structured logs:** `python-json-logger` emits single-line JSON logs (timestamp, level,
  logger, message) on stdout — ready for Loki/CloudWatch/ELK.
- **Prometheus:** enable scraping with `--set serviceMonitor.enabled=true` (requires the
  Prometheus Operator CRDs).
- **Grafana:** enable `--set grafanaDashboard.enabled=true` to ship the dashboard at
  [helm/fleet-api/dashboards/fleet-api.json](helm/fleet-api/dashboards/fleet-api.json) as a
  sidecar-discovered ConfigMap (request rate, error rate, p95 latency, in-progress requests).

### CI/CD (GitHub Actions)

Six jobs in [.github/workflows/ci.yml](.github/workflows/ci.yml):

| Job             | Trigger            | Description                                           |
| --------------- | ------------------ | ----------------------------------------------------- |
| lint-and-test   | push / PR          | ruff lint + pytest with moto (no real AWS)            |
| docker-build    | push to main       | Build + push to GHCR; tagged with SHA + latest        |
| security-scan   | after docker-build | Trivy scan; fails pipeline on CRITICAL CVEs           |
| helm-lint       | push / PR          | `helm lint` + `helm template` (no cluster needed) |
| trivy-helm      | push / PR          | Trivy misconfig scan on Helm chart (HIGH, CRITICAL)   |
| trivy-terraform | push / PR          | Trivy misconfig scan on Terraform (HIGH, CRITICAL)    |

No AWS credentials are required for CI — `moto` intercepts all boto3 calls in-process.

---

## Going to Production

This section walks through deploying the application to a real EKS cluster end-to-end. It
assumes the cluster already exists; cluster creation is out of scope (use a Terraform EKS
module).

### 1. Configure Terraform remote state

Before provisioning any infrastructure, set up an S3 backend so state is shared and
consistent across runs.

Create a dedicated state bucket (versioning + SSE enabled), then add a `backend` block to
[terraform/providers.tf](terraform/providers.tf) or a separate `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket       = "<state-bucket-name>"
    key          = "fleet-api/terraform.tfstate"
    region       = "<region>"
    use_lockfile = true   # S3-native locking, Terraform ≥ 1.10
  }
}
```

Reinitialise to migrate local state to the bucket:

```bash
terraform init -migrate-state
```

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
```

### 3. Associate the OIDC provider (IRSA)

Associate the cluster OIDC provider (idempotent):

```bash
eksctl utils associate-iam-oidc-provider --cluster <cluster-name> --approve
```

Retrieve the values needed by Terraform:

```bash
OIDC_URL=$(aws eks describe-cluster --name <cluster-name> \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"
```

### 4. Provision AWS resources

Apply Terraform against real AWS (no `localstack_endpoint`):

```bash
terraform apply \
  -var="environment=prod" \
  -var="eks_oidc_provider_arn=${OIDC_ARN}" \
  -var="eks_oidc_provider_url=${OIDC_URL}" \
  -var="k8s_namespace=default" \
  -var="k8s_service_account_name=fleet-api"
```

Note the resulting IAM role ARN for the Helm step:

```bash
terraform output iam_role_arn
```

### 5. Expose the service: Ingress + TLS

Install an Ingress controller and cert-manager if not already present in the cluster:

```bash
# AWS Load Balancer Controller (or substitute nginx-ingress)
helm repo add eks https://aws.github.io/eks-charts
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=<cluster-name>

# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set installCRDs=true
```

Create a `ClusterIssuer` for Let's Encrypt, then enable the Ingress when deploying the chart
(step 7).

### 6. Authenticate with GHCR

```bash
kubectl create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-pat-with-read-packages>
```

### 7. Deploy with Helm

```bash
helm upgrade --install fleet-api helm/fleet-api/ \
  --set image.repository=ghcr.io/<owner>/fleet-api \
  --set image.tag=<sha> \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IAM_ROLE_ARN> \
  --set imagePullSecrets[0].name=ghcr-creds \
  --set config.dynamodbTable=devices-prod \
  --set config.s3Bucket=fleet-firmware-prod \
  --set serviceMonitor.enabled=true \
  --set grafanaDashboard.enabled=true \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=<your-domain>
```

No `config.awsEndpointUrl` — pods authenticate via IRSA and reach real AWS endpoints
directly.

### 8. Verify

```bash
scripts/smoke.sh https://<your-domain>
```
# iot-fleet-devops-playground
# iot-fleet-devops-playground
