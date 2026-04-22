# =========================================================================================
# MAKEFILE - ORQUESTRAÇÃO UNIFICADA (AWS REAL & LOCALSTACK PRO)
# =========================================================================================

-include .env
export

# VALORES PADRÃO
AWS_ACCOUNT_ID      := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "000000000000")
GIT_SHA_LOCAL       := $(shell git rev-parse HEAD 2>/dev/null || echo "latest")
DEFAULT_ROLE_ARN    := $(shell aws iam get-role --role-name LabRole --query "Role.Arn" --output text 2>/dev/null || echo "arn:aws:iam::$(AWS_ACCOUNT_ID):role/LabRole")

# Configuração de Ambiente
DEPLOY_TARGET       ?= aws
AWS_REGION          ?= us-east-1
IMAGE_TAG           ?= $(GIT_SHA_LOCAL)
EKS_CLUSTER_NAME    ?= eks-tech-challenge

# Endpoints dinâmicos baseado no target
ifeq ($(DEPLOY_TARGET),localstack)
    AWS_CMD         := awslocal
    DOCKER_REGISTRY := localhost:4566
    TF_DIR          := localstack
    S3_BUCKET       := tech-challenge-bucket-andromeda-local
else
    AWS_CMD         := aws
    DOCKER_REGISTRY := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
    TF_DIR          := aws
    S3_BUCKET       := tech-challenge-tf-state-$(AWS_ACCOUNT_ID)
endif

# Variáveis de Aplicação
DB_NAME             ?= garagedb
DB_PORT             ?= 5432
DB_USER             ?= postgres
AWS_RDS_DB_PASSWORD ?= postgres
DB_SSLMODE          ?= require
JWT_SECRET          ?= mysecret
USER_ADMIN_EMAIL    ?= admin2@example.com
USER_ADMIN_PASSWORD ?= Admin123!
ADMIN_DOCUMENT      ?= 42692605802

# Exportando para Terraform
export TF_VAR_cluster_role_arn := $(DEFAULT_ROLE_ARN)
export TF_VAR_db_password      := $(AWS_RDS_DB_PASSWORD)
export TF_VAR_db_name          := $(DB_NAME)
export TF_VAR_db_user          := $(DB_USER)
export TF_VAR_db_port          := $(DB_PORT)
export TF_VAR_db_sslmode       := $(DB_SSLMODE)
export TF_VAR_jwt_secret       := $(JWT_SECRET)
export TF_VAR_image_tag        := $(IMAGE_TAG)
export TF_VAR_aws_region       := $(AWS_REGION)

.PHONY: deploy-all
deploy-all: env-check
	@echo "🔍 Target atual: $(DEPLOY_TARGET)"
	@if [ "$(DEPLOY_TARGET)" = "localstack" ]; then $(MAKE) localstack-up; fi
	@$(MAKE) build-and-push-all
	@$(MAKE) terraform-apply-all

.PHONY: build-and-push-all
build-and-push-all: login-ecr
	@echo "==> Construindo Imagens Reais (Target: $(DEPLOY_TARGET))..."
	@# S1 API
	cd tech-challenge-s1 && docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-repo:$(IMAGE_TAG) .
	docker push $(DOCKER_REGISTRY)/tech-challenge-repo:$(IMAGE_TAG)
	@# Auth
	cd tech-challenge-user-authentication && docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG) .
	docker push $(DOCKER_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG)
	@# Authorizer
	cd tech-challenge-user-authorizer && docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG) .
	docker push $(DOCKER_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG)
	@# Notification
	cd tech-challenge-notification-service && docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG) .
	docker push $(DOCKER_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG)

.PHONY: terraform-apply-all
terraform-apply-all: bootstrap-s3
	@echo "==> Aplicando Terraform ($(TF_DIR))..."
	cd iac-tech-challenge-infra/$(TF_DIR) && terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && terraform apply -auto-approve
	cd iac-tech-challenge-data/$(TF_DIR) && terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && terraform apply -auto-approve
	@if [ "$(DEPLOY_TARGET)" = "aws" ]; then $(MAKE) setup-k8s-addons; fi
	cd iac-tech-challenge-gateway/$(TF_DIR) && terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && terraform apply -auto-approve

.PHONY: login-ecr
login-ecr:
	@if [ "$(DEPLOY_TARGET)" = "aws" ]; then \
		aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(DOCKER_REGISTRY); \
	fi

.PHONY: bootstrap-s3
bootstrap-s3:
	@echo "==> Verificando S3 [$(S3_BUCKET)]..."
	@$(AWS_CMD) s3 mb s3://$(S3_BUCKET) --region $(AWS_REGION) || true

.PHONY: localstack-up
localstack-up:
	@docker compose -f docker-compose.localstack.yml up -d
	@echo "Aguardando LocalStack..."
	@until docker exec tech-challenge-localstack ls /etc/localstack/init/ready.d/init-aws.sh >/dev/null 2>&1; do sleep 2; done

.PHONY: config
config:
	@printf "Deploy Target (aws/localstack) [%s]: " "$(DEPLOY_TARGET)"; read val; echo "DEPLOY_TARGET=$${val:-$(DEPLOY_TARGET)}" > .env
	@printf "LocalStack Auth Token: "; read val; echo "LOCALSTACK_AUTH_TOKEN=$$val" >> .env
	@printf "AWS Region [%s]: " "$(AWS_REGION)"; read val; echo "AWS_REGION=$${val:-$(AWS_REGION)}" >> .env
	@echo "Configurações salvas no .env!"

.PHONY: env-check
env-check:
	@if [ ! -f .env ]; then echo "Rode 'make config' primeiro"; exit 1; fi
