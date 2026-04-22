# =========================================================================================
# MAKEFILE - ORQUESTRAÇÃO DE BUILD E DEPLOY (TECH CHALLENGE FIAP)
# =========================================================================================

-include .env
export

# VALORES PADRÃO (Utilizados caso não definidos no .env)
AWS_ACCOUNT_ID      := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "000000000000")
GIT_SHA_LOCAL       := $(shell git rev-parse HEAD 2>/dev/null || echo "latest")
DEFAULT_ROLE_ARN    := $(shell aws iam get-role --role-name LabRole --query "Role.Arn" --output text 2>/dev/null || echo "arn:aws:iam::$(AWS_ACCOUNT_ID):role/LabRole")

# Variáveis solicitadas com valores default
AWS_REGION                  ?= us-east-1
IMAGE_TAG                   ?= $(GIT_SHA_LOCAL)
AWS_S3_TF_STATE_BUCKET_NAME ?= tech-challenge-tf-state-$(AWS_ACCOUNT_ID)
EKS_CLUSTER_NAME            ?= eks-tech-challenge
AWS_CLUSTER_ROLE_ARN        ?= $(DEFAULT_ROLE_ARN)

# Credenciais AWS (Geralmente pegas do ambiente/aws configure, mas aqui para o .env)
AWS_ACCESS_KEY_ID           ?= $(shell aws configure get aws_access_key_id)
AWS_SECRET_ACCESS_KEY       ?= $(shell aws configure get aws_secret_access_key)

# Banco de Dados e Segurança
DB_NAME                     ?= garagedb
DB_PORT                     ?= 5432
DB_USER                     ?= postgres
AWS_RDS_DB_PASSWORD         ?= postgres
DB_SSLMODE                  ?= require
JWT_SECRET                  ?= mysecret
JWT_REFRESH_SECRET          ?= myrefreshsecret
JWT_ISSUER                  ?= tech-challenge

# Documentação e Admin
USER_ADMIN_EMAIL            ?= admin2@example.com
USER_ADMIN_PASSWORD         ?= Admin123!
ADMIN_DOCUMENT              ?= 42692605802

# Tabelas DynamoDB
DYNAMODB_TABLE_NAME         ?= user-authentication-token
DYNAMO_AUTH_TABLE           ?= user-authentication-token

# Integrações Externas
DD_API_KEY                  ?= dummy-key
MAILTRAP_TOKEN              ?= dummy-token
SONAR_TOKEN                 ?= dummy-token

# Exportando para Terraform (Compatibilidade com módulos existentes)
export TF_VAR_cluster_role_arn := $(AWS_CLUSTER_ROLE_ARN)
export TF_VAR_db_password      := $(AWS_RDS_DB_PASSWORD)
export TF_VAR_db_name          := $(DB_NAME)
export TF_VAR_db_user          := $(DB_USER)
export TF_VAR_db_port          := $(DB_PORT)
export TF_VAR_db_sslmode       := $(DB_SSLMODE)
export TF_VAR_jwt_secret       := $(JWT_SECRET)
export TF_VAR_jwt_refresh_secret := $(JWT_REFRESH_SECRET)
export TF_VAR_jwt_issuer       := $(JWT_ISSUER)
export TF_VAR_dynamodb_table_name := $(DYNAMODB_TABLE_NAME)

HELM := $(shell if [ -f "./helm" ]; then echo "./helm"; else echo "helm"; fi)
ECR_REGISTRY := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

.PHONY: deploy-all
deploy-all: env-check deploy-infra deploy-data setup-k8s-addons deploy-s1 deploy-auth deploy-authorizer deploy-notification deploy-gateway
	@echo "==========================================================="
	@echo "==> 🚀 Todos os repositórios foram implantados com sucesso!"
	@echo "==========================================================="

.PHONY: config
config:
	@echo "==========================================================="
	@echo "  ⚙️  Configuração de Variáveis de Ambiente"
	@echo "  Pressione ENTER para manter o valor default [entre colchetes]."
	@echo "==========================================================="
	@mkdir -p .tmp
	@echo "--- Infra & AWS ---"
	@printf "AWS_REGION [%s]: " "$(AWS_REGION)"; read val; echo "AWS_REGION=$${val:-$(AWS_REGION)}" > .env
	@printf "AWS_ACCESS_KEY_ID [%s]: " "$(AWS_ACCESS_KEY_ID)"; read val; echo "AWS_ACCESS_KEY_ID=$${val:-$(AWS_ACCESS_KEY_ID)}" >> .env
	@printf "AWS_SECRET_ACCESS_KEY [%s]: " "******"; read val; echo "AWS_SECRET_ACCESS_KEY=$${val:-$(AWS_SECRET_ACCESS_KEY)}" >> .env
	@printf "AWS_S3_TF_STATE_BUCKET_NAME [%s]: " "$(AWS_S3_TF_STATE_BUCKET_NAME)"; read val; echo "AWS_S3_TF_STATE_BUCKET_NAME=$${val:-$(AWS_S3_TF_STATE_BUCKET_NAME)}" >> .env
	@printf "EKS_CLUSTER_NAME [%s]: " "$(EKS_CLUSTER_NAME)"; read val; echo "EKS_CLUSTER_NAME=$${val:-$(EKS_CLUSTER_NAME)}" >> .env
	@printf "AWS_CLUSTER_ROLE_ARN [%s]: " "$(AWS_CLUSTER_ROLE_ARN)"; read val; echo "AWS_CLUSTER_ROLE_ARN=$${val:-$(AWS_CLUSTER_ROLE_ARN)}" >> .env
	@echo "--- Banco de Dados ---"
	@printf "DB_NAME [%s]: " "$(DB_NAME)"; read val; echo "DB_NAME=$${val:-$(DB_NAME)}" >> .env
	@printf "DB_PORT [%s]: " "$(DB_PORT)"; read val; echo "DB_PORT=$${val:-$(DB_PORT)}" >> .env
	@printf "DB_USER [%s]: " "$(DB_USER)"; read val; echo "DB_USER=$${val:-$(DB_USER)}" >> .env
	@printf "AWS_RDS_DB_PASSWORD [%s]: " "$(AWS_RDS_DB_PASSWORD)"; read val; echo "AWS_RDS_DB_PASSWORD=$${val:-$(AWS_RDS_DB_PASSWORD)}" >> .env
	@printf "DB_SSLMODE [%s]: " "$(DB_SSLMODE)"; read val; echo "DB_SSLMODE=$${val:-$(DB_SSLMODE)}" >> .env
	@echo "--- Segurança & JWT ---"
	@printf "JWT_SECRET [%s]: " "$(JWT_SECRET)"; read val; echo "JWT_SECRET=$${val:-$(JWT_SECRET)}" >> .env
	@printf "JWT_REFRESH_SECRET [%s]: " "$(JWT_REFRESH_SECRET)"; read val; echo "JWT_REFRESH_SECRET=$${val:-$(JWT_REFRESH_SECRET)}" >> .env
	@printf "JWT_ISSUER [%s]: " "$(JWT_ISSUER)"; read val; echo "JWT_ISSUER=$${val:-$(JWT_ISSUER)}" >> .env
	@echo "--- Usuário Admin ---"
	@printf "USER_ADMIN_EMAIL [%s]: " "$(USER_ADMIN_EMAIL)"; read val; echo "USER_ADMIN_EMAIL=$${val:-$(USER_ADMIN_EMAIL)}" >> .env
	@printf "USER_ADMIN_PASSWORD [%s]: " "$(USER_ADMIN_PASSWORD)"; read val; echo "USER_ADMIN_PASSWORD=$${val:-$(USER_ADMIN_PASSWORD)}" >> .env
	@printf "ADMIN_DOCUMENT [%s]: " "$(ADMIN_DOCUMENT)"; read val; echo "ADMIN_DOCUMENT=$${val:-$(ADMIN_DOCUMENT)}" >> .env
	@echo "--- DynamoDB ---"
	@printf "DYNAMODB_TABLE_NAME [%s]: " "$(DYNAMODB_TABLE_NAME)"; read val; echo "DYNAMODB_TABLE_NAME=$${val:-$(DYNAMODB_TABLE_NAME)}" >> .env
	@printf "DYNAMO_AUTH_TABLE [%s]: " "$(DYNAMO_AUTH_TABLE)"; read val; echo "DYNAMO_AUTH_TABLE=$${val:-$(DYNAMO_AUTH_TABLE)}" >> .env
	@echo "--- Integrações ---"
	@printf "DD_API_KEY [%s]: " "$(DD_API_KEY)"; read val; echo "DD_API_KEY=$${val:-$(DD_API_KEY)}" >> .env
	@printf "MAILTRAP_TOKEN [%s]: " "$(MAILTRAP_TOKEN)"; read val; echo "MAILTRAP_TOKEN=$${val:-$(MAILTRAP_TOKEN)}" >> .env
	@printf "SONAR_TOKEN [%s]: " "$(SONAR_TOKEN)"; read val; echo "SONAR_TOKEN=$${val:-$(SONAR_TOKEN)}" >> .env
	@printf "IMAGE_TAG [%s]: " "$(IMAGE_TAG)"; read val; echo "IMAGE_TAG=$${val:-$(IMAGE_TAG)}" >> .env
	@echo "==========================================================="
	@echo "✅ Variáveis salvas no arquivo '.env'!"
	@echo "==========================================================="

.PHONY: env-check
env-check:
	@if [ ! -f .env ]; then \
		echo "⚠️  Arquivo .env não encontrado. Execute 'make config' primeiro."; \
		exit 1; \
	fi

.PHONY: bootstrap-s3
bootstrap-s3:
	@echo "==> Verificando bucket S3 [$(AWS_S3_TF_STATE_BUCKET_NAME)]..."
	@if ! aws s3 ls "s3://$(AWS_S3_TF_STATE_BUCKET_NAME)" > /dev/null 2>&1; then \
		aws s3 mb s3://$(AWS_S3_TF_STATE_BUCKET_NAME) --region $(AWS_REGION) || true; \
	else \
		echo "Bucket já existe."; \
	fi

.PHONY: login-ecr
login-ecr:
	@echo "==> Autenticando Docker no Amazon ECR..."
	@aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_REGISTRY)

.PHONY: setup-k8s-addons
setup-k8s-addons:
	@echo "==> Configurando Add-ons do Kubernetes..."
	@aws eks update-kubeconfig --region $(AWS_REGION) --name $(EKS_CLUSTER_NAME)
	@kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || true
	@kubectl patch -n kube-system deployment metrics-server --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true
	@$(eval VPC_ID=$(shell aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eks-tech-challenge-vpc" --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo ""))
	@if [ -n "$(VPC_ID)" ]; then \
		$(HELM) repo add eks https://aws.github.io/eks-charts && $(HELM) repo update eks; \
		$(HELM) upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
			-n kube-system --set clusterName=$(EKS_CLUSTER_NAME) --set region=$(AWS_REGION) --set vpcId=$(VPC_ID) --set serviceAccount.create=true --wait || true; \
	fi
	@INSTANCES=$$(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/$(EKS_CLUSTER_NAME),Values=owned" --query "Reservations[*].Instances[*].InstanceId" --output text); \
	for id in $$INSTANCES; do aws ec2 modify-instance-metadata-options --instance-id $$id --http-put-response-hop-limit 2 || true; done
	@kubectl rollout restart deployment aws-load-balancer-controller -n kube-system || true

.PHONY: deploy-infra
deploy-infra: bootstrap-s3
	@echo "==> 1. Deploy [iac-tech-challenge-infra]"
	@cd iac-tech-challenge-infra/aws && \
		terraform init -input=false -reconfigure -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" && \
		terraform apply -auto-approve

.PHONY: deploy-data
deploy-data: bootstrap-s3
	@echo "==> 2. Deploy [iac-tech-challenge-data]"
	@cd iac-tech-challenge-data/aws && \
		terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" -backend-config="region=$(AWS_REGION)" && \
		terraform apply -auto-approve

.PHONY: deploy-s1
deploy-s1: login-ecr
	@echo "==> 3. Build e Deploy [tech-challenge-s1]"
	@cd tech-challenge-s1 && docker build --platform linux/amd64 -t $(ECR_REGISTRY)/tech-challenge-repo:latest . && docker push $(ECR_REGISTRY)/tech-challenge-repo:latest
	@$(eval RDS_ADDRESS=$(shell aws rds describe-db-instances --db-instance-identifier garagedb --query "DBInstances[0].Endpoint.Address" --output text 2>/dev/null || echo "localhost"))
	@mkdir -p tech-challenge-s1/k8s/overlays/aws
	@printf "DB_PASSWORD=$(AWS_RDS_DB_PASSWORD)\nJWT_SECRET=$(JWT_SECRET)\nADMIN_PASSWORD=$(USER_ADMIN_PASSWORD)\nADMIN_EMAIL=$(USER_ADMIN_EMAIL)\nADMIN_DOCUMENT=$(ADMIN_DOCUMENT)\n" > tech-challenge-s1/k8s/overlays/aws/.env.secrets
	@printf "DB_HOST=$(RDS_ADDRESS)\nDD_SERVICE=tech-challenge-api\nDD_VERSION=$(IMAGE_TAG)\nDD_SITE=datadoghq.com\n" > tech-challenge-s1/k8s/overlays/aws/.env.host
	@cd tech-challenge-s1 && kubectl kustomize k8s/overlays/aws | sed "s|ECR_IMAGE:latest|$(ECR_REGISTRY)/tech-challenge-repo:latest|g" | kubectl apply -f -
	@kubectl rollout restart deployment tech-challenge-api

.PHONY: deploy-auth
deploy-auth: bootstrap-s3 login-ecr
	@echo "==> 4. Build e Deploy [tech-challenge-user-authentication]"
	@cd tech-challenge-user-authentication && docker build --platform linux/amd64 --provenance=false -t $(ECR_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG) . && docker push $(ECR_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG)
	@$(eval RDS_ADDRESS=$(shell aws rds describe-db-instances --db-instance-identifier garagedb --query "DBInstances[0].Endpoint.Address" --output text 2>/dev/null || echo "localhost"))
	@$(eval DYNAMO_ENDPOINT=$(shell aws dynamodb describe-endpoints --query "Endpoints[0].Address" --output text 2>/dev/null || echo "dynamodb.$(AWS_REGION).amazonaws.com"))
	@cd tech-challenge-user-authentication/terraform && terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" -backend-config="region=$(AWS_REGION)" && \
		terraform apply -auto-approve -var="image_tag=$(IMAGE_TAG)" -var="db_host=$(RDS_ADDRESS)" -var="dynamodb_endpoint=https://$(DYNAMO_ENDPOINT)"

.PHONY: deploy-authorizer
deploy-authorizer: bootstrap-s3 login-ecr
	@echo "==> 5. Build e Deploy [tech-challenge-user-authorizer]"
	@cd tech-challenge-user-authorizer && docker build --platform linux/amd64 --provenance=false -t $(ECR_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG) . && docker push $(ECR_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG)
	@$(eval DYNAMO_ENDPOINT=$(shell aws dynamodb describe-endpoints --query "Endpoints[0].Address" --output text 2>/dev/null || echo "dynamodb.$(AWS_REGION).amazonaws.com"))
	@cd tech-challenge-user-authorizer/terraform && terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" -backend-config="region=$(AWS_REGION)" && \
		terraform apply -auto-approve -var="image_tag=$(IMAGE_TAG)" -var="dynamodb_endpoint=https://$(DYNAMO_ENDPOINT)"

.PHONY: deploy-notification
deploy-notification: bootstrap-s3 login-ecr
	@echo "==> 6. Build e Deploy [tech-challenge-notification-service]"
	@cd tech-challenge-notification-service && docker build --platform linux/amd64 --provenance=false -t $(ECR_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG) . && docker push $(ECR_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG)
	@cd tech-challenge-notification-service/terraform && terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" -backend-config="region=$(AWS_REGION)" && \
		terraform apply -auto-approve -var="image_tag=$(IMAGE_TAG)"

.PHONY: wait-for-alb
wait-for-alb:
	@echo "==> Aguardando ALB..."
	@timeout=600; elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		alb_arn=$$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-default-techchal')].LoadBalancerArn" --output text 2>/dev/null); \
		if [ -n "$$alb_arn" ]; then echo "ALB Detectado: $$alb_arn"; break; fi; \
		sleep 10; elapsed=$$((elapsed + 10)); \
	done

.PHONY: deploy-gateway
deploy-gateway: bootstrap-s3 wait-for-alb
	@echo "==> 7. Deploy [iac-tech-challenge-gateway]"
	@cd iac-tech-challenge-gateway/aws && terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" && terraform apply -auto-approve
	@aws eks update-kubeconfig --name $(EKS_CLUSTER_NAME) --region $(AWS_REGION)
	@kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system || true
