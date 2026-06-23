.DEFAULT_GOAL := help

APP_DIR        := app
TERRAFORM_DIR  := terraform
HELM_DIR       := helm/fleet-api
LOCALSTACK_URL := http://localhost:4566

.PHONY: help install test lint smoke build up down infra-init infra-apply infra-destroy helm-lint helm-dry-run minikube-smoke

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Dev
install: ## Install Python dependencies via Poetry
	cd $(APP_DIR) && poetry install

test: ## Run tests with moto AWS mocks
	cd $(APP_DIR) && poetry run pytest --cov=fleet_api --cov-report=term-missing

lint: ## Lint source and tests with ruff
	cd $(APP_DIR) && poetry run ruff check fleet_api tests

smoke: ## Smoke-test the live stack (requires: make up && make infra-apply)
	@scripts/smoke.sh http://localhost:8000 $(LOCALSTACK_URL)

##@ Docker
build: ## Build Docker image locally
	docker build -t fleet-api:local $(APP_DIR)

up: ## Start LocalStack + app via Docker Compose
	docker compose up -d --wait --remove-orphans

rebuild: ## Rebuild the app image and restart the stack
	docker compose build app
	docker compose up -d --wait --remove-orphans

down: ## Stop and remove containers and volumes
	docker compose down -v --remove-orphans

##@ Infra
infra-init: ## Terraform init
	terraform -chdir=$(TERRAFORM_DIR) init

infra-apply: ## Terraform apply against LocalStack
	terraform -chdir=$(TERRAFORM_DIR) apply \
	  -var="localstack_endpoint=$(LOCALSTACK_URL)" \
	  -var="environment=local" \
	  -auto-approve

infra-destroy: ## Terraform destroy against LocalStack
	terraform -chdir=$(TERRAFORM_DIR) destroy \
	  -var="localstack_endpoint=$(LOCALSTACK_URL)" \
	  -var="environment=local" \
	  -auto-approve

##@ Helm
helm-lint: ## Lint the Helm chart
	helm lint $(HELM_DIR)

helm-dry-run: ## Render Helm templates locally without a cluster
	helm template --generate-name $(HELM_DIR)

##@ Minikube
MINIKUBE_RELEASE := fleet-api-local

minikube-start: ## Start minikube if not already running
	minikube status --format='{{.Host}}' 2>/dev/null | grep -q Running || minikube start

minikube-build: ## Build the app image inside minikube's Docker daemon
	eval $$(minikube docker-env) && docker build -t fleet-api:local $(APP_DIR)

minikube-deploy: ## Install or upgrade the Helm chart on minikube
	helm upgrade --install $(MINIKUBE_RELEASE) $(HELM_DIR) -f $(HELM_DIR)/values-local.yaml

minikube-up: minikube-start minikube-build minikube-deploy ## Full setup: start minikube, build image, deploy chart

minikube-url: ## Print the service URL
	minikube service $(MINIKUBE_RELEASE) --url

minikube-delete: ## Remove the Helm release from minikube
	helm uninstall $(MINIKUBE_RELEASE) --ignore-not-found

minikube-stop: ## Stop minikube
	minikube stop

minikube-smoke: ## Smoke-test the app on Minikube (requires: make minikube-up && make infra-apply)
	$(eval MINK_IP   := $(shell minikube ip 2>/dev/null))
	$(eval MINK_PORT := $(shell kubectl get svc $(MINIKUBE_RELEASE) \
	                      -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null))
	@echo "==> Service URL: http://$(MINK_IP):$(MINK_PORT)"
	@scripts/smoke.sh http://$(MINK_IP):$(MINK_PORT) $(LOCALSTACK_URL)
