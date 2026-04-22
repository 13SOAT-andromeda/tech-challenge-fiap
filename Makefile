# =========================================================================================
# MAKEFILE - ORQUESTRAÇÃO DE BUILD E DEPLOY (TECH CHALLENGE FIAP)
# =========================================================================================

-include .env
export

# VALORES DINÂMICOS (Simulando o GitHub Actions na sua máquina local)
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "<seu-aws-account-id>")
GIT_SHA_LOCAL  := $(shell git rev-parse HEAD 2>/dev/null || echo "latest")
AWS_ROLE_ARN   := $(shell aws iam get-role --role-name LabRole --query "Role.Arn" --output text 2>/dev/null || aws iam get-role --role-name LabEksClusterRole --query "Role.Arn" --output text 2>/dev/null || echo "arn:aws:iam::$(AWS_ACCOUNT_ID):role/LabRole")
HELM           := $(shell if [ -f "./helm" ]; then echo "./helm"; else echo "helm"; fi)

AWS_REGION                  ?= us-east-1
IMAGE_TAG                   ?= $(GIT_SHA_LOCAL)
AWS_S3_TF_STATE_BUCKET_NAME ?= tech-challenge-tf-state-$(AWS_ACCOUNT_ID)
EKS_CLUSTER_NAME            ?= eks-tech-challenge
ECR_REGISTRY                ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

# Terraform vars
export TF_VAR_cluster_role_arn ?= $(AWS_ROLE_ARN)
export TF_VAR_db_password      ?= postgres
export TF_VAR_jwt_secret       ?= mysecret
export TF_VAR_jwt_refresh_secret ?= myrefreshsecret
export TF_VAR_jwt_issuer       ?= tech-challenge
export TF_VAR_db_name          ?= garagedb
export TF_VAR_db_user          ?= postgres
export TF_VAR_db_port          ?= 5432
export TF_VAR_db_sslmode       ?= require
export TF_VAR_dynamodb_table_name ?= user-authentication-token
export TF_VAR_dd_key           ?= dummy-key

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
	@printf "AWS_REGION [%s]: " "$(AWS_REGION)"; read val; echo "AWS_REGION=$${val:-$(AWS_REGION)}" > .env
	@printf "IMAGE_TAG (para Lambdas) [%s]: " "$(IMAGE_TAG)"; read val; echo "IMAGE_TAG=$${val:-$(IMAGE_TAG)}" >> .env
	@printf "AWS_S3_TF_STATE_BUCKET_NAME [%s]: " "$(AWS_S3_TF_STATE_BUCKET_NAME)"; read val; echo "AWS_S3_TF_STATE_BUCKET_NAME=$${val:-$(AWS_S3_TF_STATE_BUCKET_NAME)}" >> .env
	@printf "EKS_CLUSTER_NAME [%s]: " "$(EKS_CLUSTER_NAME)"; read val; echo "EKS_CLUSTER_NAME=$${val:-$(EKS_CLUSTER_NAME)}" >> .env
	@printf "ECR_REGISTRY [%s]: " "$(ECR_REGISTRY)"; read val; echo "ECR_REGISTRY=$${val:-$(ECR_REGISTRY)}" >> .env
	@printf "TF_VAR_db_password [%s]: " "$(TF_VAR_db_password)"; read val; echo "TF_VAR_db_password=$${val:-$(TF_VAR_db_password)}" >> .env
	@echo "==========================================================="
	@echo "✅ Variáveis salvas no arquivo '.env' e exportadas para o ambiente!"
	@echo "Você pode rodar: make deploy-all"
	@echo "==========================================================="

.PHONY: env-check
env-check:
	@if [ ! -f .env ]; then \
		echo "⚠️  Arquivo .env não encontrado."; \
		echo "Por favor, execute 'make config' primeiro para confirmar ou definir suas variáveis (como o AWS Account ID dinâmico)."; \
		exit 1; \
	fi

.PHONY: bootstrap-s3
bootstrap-s3:
	@echo "==> Verificando existência do bucket S3 [$(AWS_S3_TF_STATE_BUCKET_NAME)]..."
	@if ! aws s3 ls "s3://$(AWS_S3_TF_STATE_BUCKET_NAME)" > /dev/null 2>&1; then \
		echo "O bucket não existe. Criando em [$(AWS_REGION)]..."; \
		aws s3 mb s3://$(AWS_S3_TF_STATE_BUCKET_NAME) --region $(AWS_REGION) || true; \
		echo "Aguardando propagação do S3..."; \
		sleep 10; \
	else \
		echo "Bucket já existe."; \
	fi

.PHONY: login-ecr
login-ecr:
	@echo "==> Autenticando Docker no Amazon ECR..."
	@aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_REGISTRY)

.PHONY: setup-k8s-addons
setup-k8s-addons:
	@echo "==> Configurando Add-ons do Kubernetes (Metrics, ALB, Datadog)..."
	@aws eks update-kubeconfig --region $(AWS_REGION) --name $(EKS_CLUSTER_NAME)
	@echo "Instalando Metrics Server..."
	@kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || true
	@kubectl patch -n kube-system deployment metrics-server --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true
	@echo "Instalando AWS Load Balancer Controller..."
	@$(eval VPC_ID=$(shell aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eks-tech-challenge-vpc" --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo ""))
	@if [ -n "$(VPC_ID)" ]; then \
		$(HELM) repo add eks https://aws.github.io/eks-charts && $(HELM) repo update eks; \
		$(HELM) upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
			-n kube-system \
			--set clusterName=$(EKS_CLUSTER_NAME) \
			--set region=$(AWS_REGION) \
			--set vpcId=$(VPC_ID) \
			--set serviceAccount.create=true \
			--wait || true; \
	fi
	@echo "Ajustando Hop Limit para acesso ao IMDS (Nodes)..."
	@INSTANCES=$$(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/$(EKS_CLUSTER_NAME),Values=owned" --query "Reservations[*].Instances[*].InstanceId" --output text); \
	for id in $$INSTANCES; do \
		aws ec2 modify-instance-metadata-options --instance-id $$id --http-put-response-hop-limit 2 || true; \
	done
	@kubectl rollout restart deployment aws-load-balancer-controller -n kube-system || true
	@echo "Instalando Datadog Operator..."
	@$(HELM) repo add datadog https://helm.datadoghq.com && $(HELM) repo update datadog
	@$(HELM) upgrade --install datadog-operator datadog/datadog-operator --wait || true

.PHONY: deploy-infra
deploy-infra: bootstrap-s3
	@echo "==> 1. Deploy [iac-tech-challenge-infra]"
	@cd iac-tech-challenge-infra/aws && \
		terraform init -input=false -reconfigure -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" && \
		terraform apply -auto-approve -input=false

.PHONY: deploy-data
deploy-data: bootstrap-s3
	@echo "==> 2. Deploy [iac-tech-challenge-data]"
	@cd iac-tech-challenge-data/aws && \
		terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" -backend-config="region=$(AWS_REGION)" && \
		terraform apply -auto-approve

.PHONY: deploy-s1
deploy-s1: login-ecr
	@echo "==> 3. Build e Deploy [tech-challenge-s1] com tag 'latest'"
	@cd tech-challenge-s1 && \
		docker build --platform linux/amd64 -t $(ECR_REGISTRY)/tech-challenge-repo:latest . && \
		docker push $(ECR_REGISTRY)/tech-challenge-repo:latest
	@echo "==> Gerando arquivos de env para o Kustomize (s1)..."
	@$(eval RDS_ADDRESS=$(shell aws rds describe-db-instances --db-instance-identifier garagedb --query "DBInstances[0].Endpoint.Address" --output text 2>/dev/null || echo "localhost"))
	@mkdir -p tech-challenge-s1/k8s/overlays/aws
	@printf "DB_PASSWORD=$(TF_VAR_db_password)\nJWT_SECRET=$(TF_VAR_jwt_secret)\nADMIN_PASSWORD=Admin123!\nADMIN_EMAIL=admin2@example.com\nADMIN_DOCUMENT=42692605802\n" > tech-challenge-s1/k8s/overlays/aws/.env.secrets
	@printf "DB_HOST=$(RDS_ADDRESS)\nDD_SERVICE=tech-challenge-api\nDD_VERSION=$(IMAGE_TAG)\nDD_SITE=datadoghq.com\n" > tech-challenge-s1/k8s/overlays/aws/.env.host
	@echo "==> Aplicando manifestos do Kustomize (s1)..."
	@cd tech-challenge-s1 && \
		kubectl kustomize k8s/overlays/aws | \
		sed "s|ECR_IMAGE:latest|$(ECR_REGISTRY)/tech-challenge-repo:latest|g" | \
		kubectl apply -f -
	@echo "==> Reiniciando o deployment da API (s1)..."
	@kubectl rollout restart deployment tech-challenge-api

.PHONY: deploy-auth
deploy-auth: bootstrap-s3 login-ecr
	@echo "==> 4. Build e Deploy [tech-challenge-user-authentication] com tag '$(IMAGE_TAG)'"
	@cd tech-challenge-user-authentication && \
		docker build --platform linux/amd64 --provenance=false -t $(ECR_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG) . && \
		docker push $(ECR_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG)
	@echo "==> Aplicando Terraform (Lambda User Auth)..."
	@$(eval RDS_ADDRESS=$(shell aws rds describe-db-instances --db-instance-identifier garagedb --query "DBInstances[0].Endpoint.Address" --output text 2>/dev/null || echo "localhost"))
	@$(eval DYNAMO_ENDPOINT=$(shell aws dynamodb describe-endpoints --query "Endpoints[0].Address" --output text 2>/dev/null || echo "dynamodb.$(AWS_REGION).amazonaws.com"))
	@cd tech-challenge-user-authentication/terraform && \
		terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" -backend-config="region=$(AWS_REGION)" && \
		terraform apply -auto-approve \
			-var="image_tag=$(IMAGE_TAG)" \
			-var="db_host=$(RDS_ADDRESS)" \
			-var="dynamodb_endpoint=https://$(DYNAMO_ENDPOINT)"

.PHONY: deploy-authorizer
deploy-authorizer: bootstrap-s3 login-ecr
	@echo "==> 5. Build e Deploy [tech-challenge-user-authorizer] com tag '$(IMAGE_TAG)'"
	@cd tech-challenge-user-authorizer && \
		docker build --platform linux/amd64 --provenance=false -t $(ECR_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG) . && \
		docker push $(ECR_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG)
	@echo "==> Aplicando Terraform (Lambda User Authorizer)..."
	@$(eval DYNAMO_ENDPOINT=$(shell aws dynamodb describe-endpoints --query "Endpoints[0].Address" --output text 2>/dev/null || echo "dynamodb.$(AWS_REGION).amazonaws.com"))
	@cd tech-challenge-user-authorizer/terraform && \
		terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" -backend-config="region=$(AWS_REGION)" && \
		terraform apply -auto-approve \
			-var="image_tag=$(IMAGE_TAG)" \
			-var="dynamodb_endpoint=https://$(DYNAMO_ENDPOINT)"

.PHONY: deploy-notification
deploy-notification: bootstrap-s3 login-ecr
	@echo "==> 6. Build e Deploy [tech-challenge-notification-service] com tag '$(IMAGE_TAG)'"
	@cd tech-challenge-notification-service && \
		docker build --platform linux/amd64 --provenance=false -t $(ECR_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG) . && \
		docker push $(ECR_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG)
	@cd tech-challenge-notification-service/terraform && \
		terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" -backend-config="region=$(AWS_REGION)" && \
		terraform apply -auto-approve \
			-var="image_tag=$(IMAGE_TAG)"

.PHONY: wait-for-alb
wait-for-alb:
	@echo "==> Aguardando o AWS Load Balancer (ALB) ser provisionado pelo Ingress..."
	@timeout=600; elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		alb_arn=$$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-default-techchal')].LoadBalancerArn" --output text 2>/dev/null); \
		if [ -z "$$alb_arn" ]; then \
			alb_arn=$$(aws elbv2 describe-load-balancers --query "LoadBalancers[?Tags[?Key=='kubernetes.io/ingress/name' && Value=='tech-challenge-api-ingress']].LoadBalancerArn" --output text 2>/dev/null); \
		fi; \
		if [ -n "$$alb_arn" ]; then \
			echo "ALB Detectado: $$alb_arn"; \
			break; \
		fi; \
		echo "Aguardando ALB... ($$elapsed/$$timeout s)"; \
		sleep 10; \
		elapsed=$$((elapsed + 10)); \
	done; \
	if [ -z "$$alb_arn" ]; then echo "Timeout aguardando ALB"; exit 1; fi

.PHONY: deploy-gateway
deploy-gateway: bootstrap-s3 wait-for-alb
	@echo "==> 7. Deploy [iac-tech-challenge-gateway]"
	@cd iac-tech-challenge-gateway/aws && \
		terraform init -backend-config="bucket=$(AWS_S3_TF_STATE_BUCKET_NAME)" && \
		terraform apply -auto-approve
	@echo "==> Atualizando credenciais no AWS Load Balancer Controller (Gateway)..."
	@aws eks update-kubeconfig --name $(EKS_CLUSTER_NAME) --region $(AWS_REGION)
	@kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system || true
	@kubectl rollout status deployment/aws-load-balancer-controller -n kube-system || true
