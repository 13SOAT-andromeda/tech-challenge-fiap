# =========================================================================================
# MAKEFILE - ORQUESTRAÇÃO UNIFICADA (AWS REAL & LOCALSTACK PRO)
# Convenção de targets: localstack-* para local, aws-* para AWS, sem prefixo = compartilhado
# =========================================================================================

-include .env
export

# -------------------------------------------------------------------------------------
# VALORES PADRÃO
# -------------------------------------------------------------------------------------
AWS_ACCOUNT_ID      := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "000000000000")
GIT_SHA_LOCAL       := $(shell git rev-parse HEAD 2>/dev/null || echo "latest")
DEFAULT_ROLE_ARN    := $(shell aws iam get-role --role-name LabRole --query "Role.Arn" --output text 2>/dev/null || echo "arn:aws:iam::$(AWS_ACCOUNT_ID):role/LabRole")

# -------------------------------------------------------------------------------------
# CONFIGURAÇÃO DE AMBIENTE
# -------------------------------------------------------------------------------------
DEPLOY_TARGET       ?= localstack
AWS_REGION          ?= us-east-1
IMAGE_TAG           ?= $(GIT_SHA_LOCAL)
EKS_CLUSTER_NAME    ?= eks-tech-challenge

# Endpoints e diretórios Terraform baseados no target
ifeq ($(DEPLOY_TARGET),localstack)
    AWS_CMD         := awslocal
    # ECR_ENDPOINT_STRATEGY=off → todos os repos usam localhost.localstack.cloud:4510
    DOCKER_REGISTRY := localhost.localstack.cloud:4510
    TF_DIR          := localstack
    S3_BUCKET       := tech-challenge-bucket-andromeda-local
    DB_PORT         ?= 4512
else
    AWS_CMD         := aws
    DOCKER_REGISTRY := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
    TF_DIR          := aws
    S3_BUCKET       := tech-challenge-tf-state-$(AWS_ACCOUNT_ID)
    DB_PORT         ?= 5432
endif

# -------------------------------------------------------------------------------------
# VARIÁVEIS DE APLICAÇÃO
# -------------------------------------------------------------------------------------
DB_NAME             ?= garagedb
DB_USER             ?= postgres
CATALOG_DB_INSTANCE ?= catalog-db-instance
CATALOG_DB_NAME     ?= catalog_db
AWS_RDS_DB_PASSWORD ?= postgres
DB_SSLMODE          ?= require
JWT_SECRET          ?= secretlocalstack
USER_ADMIN_EMAIL    ?= admin2@example.com
USER_ADMIN_PASSWORD ?= Admin123!
ADMIN_DOCUMENT      ?= 42692605802

# Notification service
NOTIFICATION_S3_BUCKET       ?= tech-challenge-notification-templates
NOTIFICATION_EVENTS_TOPIC    ?= notification-events-topic
NOTIFICATION_QUEUE           ?= notification-queue
NOTIFICATION_DEFAULT_EMAIL   ?= $(USER_ADMIN_EMAIL)
NOTIFICATION_DEFAULT_NAME    ?= Administrador
MAILTRAP_TOKEN               ?= 6a45f171cfc233e4edc93d8b847cf19f
MAILTRAP_URL                 ?= https://send.api.mailtrap.io/api
MAILTRAP_FROM_EMAIL          ?= contato@nohats.net.br
MAILTRAP_FROM_NAME           ?= Nohats

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

# =========================================================================================
# TARGETS COMPARTILHADOS
# =========================================================================================

.PHONY: help
help:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════════╗"
	@echo "║         TECH CHALLENGE - ORQUESTRAÇÃO DE INFRAESTRUTURA         ║"
	@echo "╠══════════════════════════════════════════════════════════════════╣"
	@echo "║  COMPARTILHADOS                                                  ║"
	@echo "║    make setup               Wizard interativo — cria .env        ║"
	@echo "║    make env-check           Valida existência do .env            ║"
	@echo "╠══════════════════════════════════════════════════════════════════╣"
	@echo "║  LOCALSTACK (desenvolvimento local)                              ║"
	@echo "║    make localstack-up-all      Setup completo (primeira vez)     ║"
	@echo "║    make localstack-restart     Recupera após reboot do PC        ║"
	@echo "║    make localstack-start       Inicia container LocalStack       ║"
	@echo "║    make localstack-create-lambdas  Recria as 3 funções Lambda    ║"
	@echo "║    make localstack-start-catalog   Build+run catalog-api container║"
	@echo "║    make localstack-apply-patch Aplica patch pull_image           ║"
	@echo "║    make localstack-create-notification-infra  SNS+SQS notif     ║"
	@echo "║    make localstack-upload-notification-templates  Templates S3  ║"
	@echo "║    make localstack-bootstrap   Cria bucket S3 de estado          ║"
	@echo "║    make localstack-tf-infra    Aplica iac-tech-challenge-infra   ║"
	@echo "║    make localstack-tf-data     Aplica iac-tech-challenge-data    ║"
	@echo "║    make localstack-tf-gateway  Aplica iac-tech-challenge-gateway ║"
	@echo "║    make localstack-seed-admin  Seed do usuário admin no RDS      ║"
	@echo "║    make localstack-push-images Build+push imagens (opcional)     ║"
	@echo "║    make localstack-down        Para container (mantém estado)    ║"
	@echo "║    make localstack-clean       Para container + apaga volume     ║"
	@echo "╠══════════════════════════════════════════════════════════════════╣"
	@echo "║  AWS (produção / CI)                                             ║"
	@echo "║    make aws-deploy-all      Deploy completo na AWS               ║"
	@echo "║    make aws-push-images     Build+push todas as imagens no ECR   ║"
	@echo "║    make aws-tf-all          Aplica todas as camadas Terraform     ║"
	@echo "║    make aws-tf-infra        Aplica iac-tech-challenge-infra/aws  ║"
	@echo "║    make aws-tf-data         Aplica iac-tech-challenge-data/aws   ║"
	@echo "║    make aws-tf-gateway      Aplica iac-tech-challenge-gateway/aws║"
	@echo "║    make aws-setup-k8s       Configura addons EKS                 ║"
	@echo "╚══════════════════════════════════════════════════════════════════╝"
	@echo ""

.PHONY: setup
setup:
	@echo ""
	@echo "==> Configuração Interativa do Ambiente"
	@printf "Deploy Target (localstack/aws) [$(DEPLOY_TARGET)]: "; read val; \
	  TARGET=$${val:-$(DEPLOY_TARGET)}; \
	  echo "DEPLOY_TARGET=$$TARGET" > .env; \
	  if [ "$$TARGET" = "localstack" ]; then \
	    printf "LocalStack Auth Token [$(LOCALSTACK_AUTH_TOKEN)]: "; read val; \
	      echo "LOCALSTACK_AUTH_TOKEN=$${val:-$(LOCALSTACK_AUTH_TOKEN)}" >> .env; \
	  fi; \
	  printf "AWS Region [$(AWS_REGION)]: "; read val; \
	    echo "AWS_REGION=$${val:-$(AWS_REGION)}" >> .env; \
	  printf "DB Password [$(AWS_RDS_DB_PASSWORD)]: "; read val; \
	    echo "AWS_RDS_DB_PASSWORD=$${val:-$(AWS_RDS_DB_PASSWORD)}" >> .env; \
	  printf "JWT Secret [$(JWT_SECRET)]: "; read val; \
	    echo "JWT_SECRET=$${val:-$(JWT_SECRET)}" >> .env; \
	  printf "Admin Email [$(USER_ADMIN_EMAIL)]: "; read val; \
	    echo "USER_ADMIN_EMAIL=$${val:-$(USER_ADMIN_EMAIL)}" >> .env; \
	  printf "Admin Password [$(USER_ADMIN_PASSWORD)]: "; read val; \
	    echo "USER_ADMIN_PASSWORD=$${val:-$(USER_ADMIN_PASSWORD)}" >> .env; \
	  printf "Admin CPF [$(ADMIN_DOCUMENT)]: "; read val; \
	    echo "ADMIN_DOCUMENT=$${val:-$(ADMIN_DOCUMENT)}" >> .env
	@echo ""
	@echo "==> Configurações salvas em .env!"

.PHONY: env-check
env-check:
	@if [ ! -f .env ]; then echo "Rode 'make setup' primeiro"; exit 1; fi

# =========================================================================================
# TARGETS LOCALSTACK
# =========================================================================================

.PHONY: localstack-up-all
localstack-up-all: env-check localstack-start localstack-bootstrap \
    localstack-tf-infra localstack-tf-data localstack-tf-gateway \
    localstack-seed-admin localstack-create-lambdas \
    localstack-create-notification-infra \
    localstack-upload-notification-templates \
    localstack-start-catalog
	@echo ""
	@echo "==> Infraestrutura LocalStack completa e pronta!"
	@echo "==> Testando endpoint de login..."
	@sleep 2
	@curl -s -o /dev/null -w "POST /api/sessions => HTTP %{http_code}\n" \
	  -X POST "$$(awslocal apigatewayv2 get-apis --query 'Items[0].ApiEndpoint' --output text 2>/dev/null)/api/sessions" \
	  -H "Content-Type: application/json" \
	  -d '{"document":"$(ADMIN_DOCUMENT)","password":"$(USER_ADMIN_PASSWORD)"}' 2>/dev/null || true

.PHONY: localstack-start
localstack-start:
	@echo "==> Iniciando LocalStack..."
	@docker compose -f docker-compose.localstack.yml up -d
	@echo "==> Aguardando LocalStack ficar saudável..."
	@until curl -s http://localhost:4566/_localstack/health | \
	    python3 -c "import sys,json; s=json.load(sys.stdin).get('services',{}); sys.exit(0 if s.get('lambda') in ('available','running') else 1)" 2>/dev/null; do \
	    printf '.'; sleep 3; \
	done
	@echo " LocalStack pronto!"
	@$(MAKE) localstack-apply-patch

# Recuperação após reboot do computador (container parado mas não removido)
.PHONY: localstack-restart
localstack-restart:
	@echo "==> Reiniciando LocalStack após reboot do sistema..."
	@echo "==> Limpando estado Lambda corrompido..."
	@docker run --rm -v "$(shell pwd)/.localstack-volume:/vol" alpine \
	  rm -f /vol/state/000000000000/lambda/us-east-1/store.state.avro 2>/dev/null || true
	@echo "==> Iniciando container LocalStack (preservando volume)..."
	@docker start tech-challenge-localstack 2>/dev/null || \
	  docker compose -f docker-compose.localstack.yml up -d
	@echo "==> Aguardando LocalStack ficar pronto..."
	@until curl -s http://localhost:4566/_localstack/health | \
	    python3 -c "import sys,json; s=json.load(sys.stdin).get('services',{}); sys.exit(0 if s.get('lambda') in ('available','running') else 1)" 2>/dev/null; do \
	    printf '.'; sleep 3; \
	done
	@echo " LocalStack pronto!"
	@$(MAKE) localstack-apply-patch
	@$(MAKE) localstack-create-lambdas
	@$(MAKE) localstack-create-notification-infra
	@$(MAKE) localstack-upload-notification-templates
	@$(MAKE) localstack-start-catalog
	@echo ""
	@echo "==> LocalStack restaurado! Teste: curl -X POST http://d95e0bf3.execute-api.localhost.localstack.cloud:4566/localstack/api/sessions ..."

# Aplica o patch pull_image dentro do container (usa cache Docker local em vez do registry ECR)
.PHONY: localstack-apply-patch
localstack-apply-patch:
	@echo "==> Aplicando patch pull_image no LocalStack..."
	@docker cp scripts/patch_localstack.py tech-challenge-localstack:/tmp/patch_localstack.py
	@docker exec tech-challenge-localstack \
	  /opt/code/localstack/.venv/bin/python3 /tmp/patch_localstack.py

# Acorda serviços de inicialização lazy (RDS e rotas execute-api do API Gateway)
.PHONY: localstack-init-services
localstack-init-services:
	@echo "==> Inicializando serviços lazy (RDS + API Gateway routes)..."
	@awslocal rds describe-db-instances \
	  --query 'DBInstances[].{id:DBInstanceIdentifier,status:DBInstanceStatus}' \
	  --output table 2>/dev/null || true
	@awslocal apigatewayv2 get-api --api-id d95e0bf3 --query 'ApiId' --output text 2>/dev/null || true
	@echo "==> Aguardando RDS porta 4512..."
	@until docker exec tech-challenge-localstack ss -tlnp 2>/dev/null | grep -q 4512; do \
	  printf '.'; sleep 2; \
	done
	@echo " RDS pronto!"

# Cria as 3 funções Lambda com configuração correta para LocalStack
.PHONY: localstack-create-lambdas
localstack-create-lambdas: localstack-init-services
	@echo "==> Removendo funções Lambda antigas (se existirem)..."
	@awslocal lambda delete-function --function-name tech-challenge-user-authentication 2>/dev/null || true
	@awslocal lambda delete-function --function-name tech-challenge-user-authorizer 2>/dev/null || true
	@awslocal lambda delete-function --function-name tech-challenge-notification-service 2>/dev/null || true
	@echo "==> Criando função Lambda: tech-challenge-user-authentication..."
	@awslocal lambda create-function \
	  --function-name tech-challenge-user-authentication \
	  --package-type Image \
	  --code ImageUri=$(DOCKER_REGISTRY)/tech-challenge-user-authentication-repo:latest \
	  --role arn:aws:iam::000000000000:role/eks-local-role \
	  --timeout 120 --memory-size 1024 \
	  --environment "Variables={DYNAMODB_TABLE_NAME=user-authentication-token,DB_PORT=4512,PROJECT_ENV=localstack,JWT_SECRET=$(JWT_SECRET),DB_HOST=172.18.0.2,DYNAMODB_ENDPOINT=http://172.18.0.2:4566,DD_TRACE_ENABLED=false,AWS_REGION=$(AWS_REGION),DB_PASSWORD=$(AWS_RDS_DB_PASSWORD),DB_NAME=$(DB_NAME),DD_SERVERLESS_LOGS_ENABLED=false,JWT_REFRESH_SECRET=$(JWT_SECRET),DD_API_KEY=disabled,DB_SSLMODE=disable,DB_USER=$(DB_USER)}" \
	  --query 'State' --output text 2>&1
	@echo "==> Criando função Lambda: tech-challenge-user-authorizer..."
	@awslocal lambda create-function \
	  --function-name tech-challenge-user-authorizer \
	  --package-type Image \
	  --code ImageUri=$(DOCKER_REGISTRY)/tech-challenge-user-authorizer-repo:latest \
	  --role arn:aws:iam::000000000000:role/eks-local-role \
	  --timeout 120 --memory-size 1024 \
	  --environment "Variables={DYNAMODB_TABLE_NAME=user-authentication-token,DYNAMODB_ENDPOINT=http://172.18.0.2:4566,JWT_SECRET=$(JWT_SECRET),JWT_ISSUER=tech-challenge-s1,DD_API_KEY=disabled,PROJECT_ENV=localstack,AWS_REGION=$(AWS_REGION)}" \
	  --query 'State' --output text 2>&1
	@echo "==> Criando função Lambda: tech-challenge-notification-service..."
	@awslocal lambda create-function \
	  --function-name tech-challenge-notification-service \
	  --package-type Image \
	  --code ImageUri=$(DOCKER_REGISTRY)/tech-challenge-notification-service-repo:latest \
	  --role arn:aws:iam::000000000000:role/eks-local-role \
	  --timeout 30 --memory-size 128 \
	  --environment "Variables={AWS_REGION=$(AWS_REGION),PROJECT_ENV=localstack,S3_BUCKET_NAME=$(NOTIFICATION_S3_BUCKET),MAILTRAP_TOKEN=$(MAILTRAP_TOKEN),MAILTRAP_URL=$(MAILTRAP_URL),MAILTRAP_FROM_EMAIL=$(MAILTRAP_FROM_EMAIL),MAILTRAP_FROM_NAME=$(MAILTRAP_FROM_NAME),JWT_SECRET=$(JWT_SECRET)}" \
	  --query 'State' --output text 2>&1
	@echo "==> Aguardando tech-challenge-user-authentication ficar Active..."
	@for i in $$(seq 1 20); do \
	  state=$$(awslocal lambda get-function --function-name tech-challenge-user-authentication \
	    --query 'Configuration.State' --output text 2>/dev/null); \
	  echo "  [$${i}] $${state}"; \
	  [ "$$state" = "Active" ] && break; \
	  [ "$$state" = "Failed" ] && echo "ERRO: Lambda falhou!" && exit 1; \
	  sleep 3; \
	done
	@echo "==> Funções Lambda criadas com sucesso!"

.PHONY: localstack-bootstrap
localstack-bootstrap:
	@echo "==> Criando bucket de estado S3 [$(S3_BUCKET)]..."
	@awslocal s3 mb s3://$(S3_BUCKET) --region $(AWS_REGION) 2>/dev/null || true
	@echo "==> Criando bucket S3 de templates de notificação [$(NOTIFICATION_S3_BUCKET)]..."
	@awslocal s3 mb s3://$(NOTIFICATION_S3_BUCKET) --region $(AWS_REGION) 2>/dev/null || true

.PHONY: localstack-tf-infra
localstack-tf-infra:
	@echo "==> Aplicando Terraform: iac-tech-challenge-infra/localstack..."
	cd iac-tech-challenge-infra/localstack && \
	  yes yes | terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && \
	  terraform apply -auto-approve

.PHONY: localstack-tf-data
localstack-tf-data:
	@echo "==> Aplicando Terraform: iac-tech-challenge-data/localstack..."
	cd iac-tech-challenge-data/localstack && \
	  yes yes | terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && \
	  terraform apply -auto-approve

.PHONY: localstack-tf-gateway
localstack-tf-gateway:
	@echo "==> Aplicando Terraform: iac-tech-challenge-gateway/localstack..."
	cd iac-tech-challenge-gateway/localstack && \
	  yes yes | terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && \
	  terraform apply -auto-approve

.PHONY: localstack-seed-admin
localstack-seed-admin:
	@echo "==> Populando usuário Admin no GarageDB (LocalStack)..."
	@docker exec -i tech-challenge-localstack bash -c "PGPASSWORD=$(AWS_RDS_DB_PASSWORD) psql -h localhost.localstack.cloud -p 4512 -U $(DB_USER) -d garagedb -c ' \
	CREATE TABLE IF NOT EXISTS \"Person\" ( \
		id SERIAL PRIMARY KEY, \
		created_at TIMESTAMP WITH TIME ZONE, \
		updated_at TIMESTAMP WITH TIME ZONE, \
		deleted_at TIMESTAMP WITH TIME ZONE, \
		name TEXT, \
		email TEXT UNIQUE, \
		contact TEXT, \
		document TEXT UNIQUE, \
		is_active BOOLEAN DEFAULT TRUE, \
		street TEXT, number TEXT, complement TEXT, city TEXT, state TEXT, zip_code TEXT \
	); \
	CREATE TABLE IF NOT EXISTS \"User\" ( \
		id SERIAL PRIMARY KEY, \
		created_at TIMESTAMP WITH TIME ZONE, \
		updated_at TIMESTAMP WITH TIME ZONE, \
		deleted_at TIMESTAMP WITH TIME ZONE, \
		password TEXT, \
		role TEXT, \
		person_id INTEGER REFERENCES \"Person\"(id) \
	); \
	DO \$$seed\$$ \
	DECLARE \
		new_person_id INTEGER; \
	BEGIN \
		IF NOT EXISTS (SELECT 1 FROM \"User\" u JOIN \"Person\" p ON u.person_id = p.id WHERE p.email = \$$mail\$$$(USER_ADMIN_EMAIL)\$$mail\$$) THEN \
			INSERT INTO \"Person\" (created_at, updated_at, name, email, contact, document) \
			VALUES (NOW(), NOW(), \$$name\$$Administrador\$$name\$$, \$$mail\$$$(USER_ADMIN_EMAIL)\$$mail\$$, \$$phone\$$+5511999999999\$$phone\$$, \$$doc\$$$(ADMIN_DOCUMENT)\$$doc\$$) \
			RETURNING id INTO new_person_id; \
			INSERT INTO \"User\" (created_at, updated_at, password, role, person_id) \
			VALUES (NOW(), NOW(), \$$pass\$$\$$2a\$$10\$\$.Un4nnFGBuT51I.1w8c2KuyCPG4beRXMzx4b8ka.puj2fx2/2jZZi\$$pass\$$, \$$role\$$admin\$$role\$$, new_person_id); \
			RAISE NOTICE \$$msg\$$Usuário Admin criado com sucesso.\$$msg\$$; \
		ELSE \
			RAISE NOTICE \$$msg\$$Usuário Admin já existe.\$$msg\$$; \
		END IF; \
	END \$$seed\$$;'"

# Inicia o catalog-api como container em tech-challenge-network e atualiza integração do API Gateway
.PHONY: localstack-create-catalog-rds
localstack-create-catalog-rds:
	@echo "==> Criando RDS instance separada para catalog-api..."
	@awslocal rds describe-db-instances --db-instance-identifier $(CATALOG_DB_INSTANCE) \
	  --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null | grep -q "$(CATALOG_DB_INSTANCE)" || \
	awslocal rds create-db-instance \
	  --db-instance-identifier $(CATALOG_DB_INSTANCE) \
	  --db-instance-class db.t3.micro \
	  --engine postgres \
	  --master-username $(DB_USER) \
	  --master-user-password $(AWS_RDS_DB_PASSWORD) \
	  --db-name $(CATALOG_DB_NAME) \
	  --no-publicly-accessible
	@echo "==> Aguardando RDS catalog disponível..."
	@until awslocal rds describe-db-instances \
	  --db-instance-identifier $(CATALOG_DB_INSTANCE) \
	  --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null | grep -q available; do \
	  printf '.'; sleep 3; done
	@echo " RDS catalog disponível!"
	@echo "==> Obtendo porta do catalog RDS via API..."
	@PORT=$$(awslocal rds describe-db-instances \
	  --db-instance-identifier $(CATALOG_DB_INSTANCE) \
	  --query 'DBInstances[0].Endpoint.Port' --output text 2>/dev/null); \
	echo "$$PORT" > .catalog-db-port; \
	echo "==> Aguardando PostgreSQL do catalog-db escutar na porta $$PORT..."; \
	until docker exec tech-challenge-localstack ss -tlnp 2>/dev/null | grep -q ":$$PORT"; do \
	  printf '.'; sleep 2; done; \
	echo " Catalog RDS pronto na porta $$PORT"

.PHONY: localstack-start-catalog
localstack-start-catalog: localstack-create-catalog-rds
	@echo "==> Buildando imagem tech-challenge-catalog-api..."
	@cd tech-challenge-catalog-api && \
	  docker build --platform linux/amd64 --target production \
	  -t tech-challenge-catalog-api:localstack . -q
	@echo "==> Iniciando container catalog-api..."
	@docker rm -f tech-challenge-catalog-api 2>/dev/null || true
	@CATALOG_PORT=$$(cat .catalog-db-port 2>/dev/null || echo "4513"); \
	echo "Usando catalog-db na porta $$CATALOG_PORT"; \
	docker run -d \
	  --name tech-challenge-catalog-api \
	  --network tech-challenge-network \
	  -e DATABASE_URL="postgres://$(DB_USER):$(AWS_RDS_DB_PASSWORD)@172.18.0.2:$$CATALOG_PORT/$(CATALOG_DB_NAME)?sslmode=disable" \
	  -e AWS_ENDPOINT="http://172.18.0.2:4566" \
	  -e AWS_REGION="$(AWS_REGION)" \
	  -e AWS_ACCESS_KEY_ID="test" \
	  -e AWS_SECRET_ACCESS_KEY="test" \
	  -e SNS_TOPIC_CATALOG_EVENTS_ARN="arn:aws:sns:$(AWS_REGION):000000000000:catalog-events-topic" \
	  -e SNS_TOPIC_NOTIFICATION_EVENTS_ARN="arn:aws:sns:$(AWS_REGION):000000000000:$(NOTIFICATION_EVENTS_TOPIC)" \
	  -e SQS_ORDERS_APPROVED_QUEUE_URL="http://sqs.$(AWS_REGION).localhost.localstack.cloud:4566/000000000000/orders-approved-queue" \
	  -e NOTIFICATION_DEFAULT_EMAIL="$(NOTIFICATION_DEFAULT_EMAIL)" \
	  -e NOTIFICATION_DEFAULT_NAME="$(NOTIFICATION_DEFAULT_NAME)" \
	  -e JWT_SECRET="$(JWT_SECRET)" \
	  -e HTTP_PORT="8080" \
	  tech-challenge-catalog-api:localstack
	@sleep 3
	@echo "==> Atualizando integração do API Gateway para apontar para catalog-api..."
	@BACKEND_ID=$$(awslocal apigatewayv2 get-integrations --api-id d95e0bf3 \
	  --query 'Items[?IntegrationType==`HTTP_PROXY`].IntegrationId' --output text 2>/dev/null | head -1); \
	  if [ -n "$$BACKEND_ID" ]; then \
	    awslocal apigatewayv2 update-integration \
	      --api-id d95e0bf3 \
	      --integration-id "$$BACKEND_ID" \
	      --integration-type HTTP_PROXY \
	      --integration-method ANY \
	      --integration-uri "http://tech-challenge-catalog-api:8080" \
	      --connection-type INTERNET \
	      --payload-format-version "1.0" \
	      --request-parameters '{"overwrite:path":"$$request.path"}' \
	      --query 'IntegrationUri' --output text 2>/dev/null; \
	  fi
	@echo "==> Catalog API pronta!"

.PHONY: localstack-create-notification-infra
localstack-create-notification-infra:
	@echo "==> Criando infraestrutura de notificações (SNS → SQS → Lambda)..."
	@awslocal sns create-topic \
	  --name $(NOTIFICATION_EVENTS_TOPIC) \
	  --query 'TopicArn' --output text 2>/dev/null || true
	@awslocal sqs create-queue \
	  --queue-name $(NOTIFICATION_QUEUE)-dlq \
	  --query 'QueueUrl' --output text 2>/dev/null || true
	@awslocal sqs create-queue \
	  --queue-name $(NOTIFICATION_QUEUE) \
	  --query 'QueueUrl' --output text 2>/dev/null || true
	@echo "==> Criando subscription SQS no tópico de notificações..."
	@TOPIC_ARN="arn:aws:sns:$(AWS_REGION):000000000000:$(NOTIFICATION_EVENTS_TOPIC)"; \
	QUEUE_ARN="arn:aws:sqs:$(AWS_REGION):000000000000:$(NOTIFICATION_QUEUE)"; \
	awslocal sns subscribe \
	  --topic-arn "$$TOPIC_ARN" \
	  --protocol sqs \
	  --notification-endpoint "$$QUEUE_ARN" \
	  --query 'SubscriptionArn' --output text 2>/dev/null
	@echo "==> Criando event source mapping SQS → Lambda notification-service..."
	@QUEUE_ARN="arn:aws:sqs:$(AWS_REGION):000000000000:$(NOTIFICATION_QUEUE)"; \
	UUID=$$(awslocal lambda list-event-source-mappings \
	  --function-name tech-challenge-notification-service \
	  --event-source-arn "$$QUEUE_ARN" \
	  --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null); \
	if [ -n "$$UUID" ] && [ "$$UUID" != "None" ]; then \
	  awslocal lambda delete-event-source-mapping --uuid "$$UUID" 2>/dev/null || true; \
	fi; \
	awslocal lambda create-event-source-mapping \
	  --function-name tech-challenge-notification-service \
	  --event-source-arn "$$QUEUE_ARN" \
	  --batch-size 1 \
	  --query 'UUID' --output text 2>/dev/null
	@echo "==> Infraestrutura de notificações pronta!"

.PHONY: localstack-upload-notification-templates
localstack-upload-notification-templates:
	@echo "==> Fazendo upload dos templates de email para S3 [$(NOTIFICATION_S3_BUCKET)]..."
	@awslocal s3 cp \
	  tech-challenge-notification-service/templates/STOCK_RESERVED.html \
	  s3://$(NOTIFICATION_S3_BUCKET)/templates/STOCK_RESERVED.html \
	  --metadata "subject=Estoque Reservado - Pedido em processamento" 2>/dev/null || true
	@awslocal s3 cp \
	  tech-challenge-notification-service/templates/BACKORDER_CREATED.html \
	  s3://$(NOTIFICATION_S3_BUCKET)/templates/BACKORDER_CREATED.html \
	  --metadata "subject=Backorder Criado - Item temporariamente indisponivel" 2>/dev/null || true
	@awslocal s3 cp \
	  tech-challenge-notification-service/templates/STOCK_RESERVATION_FAILED.html \
	  s3://$(NOTIFICATION_S3_BUCKET)/templates/STOCK_RESERVATION_FAILED.html \
	  --metadata "subject=Falha na Reserva de Estoque" 2>/dev/null || true
	@awslocal s3 cp \
	  tech-challenge-notification-service/templates/ORDER_APPROVAL_REQUEST.html \
	  s3://$(NOTIFICATION_S3_BUCKET)/templates/ORDER_APPROVAL_REQUEST.html \
	  --metadata "subject=Aprovacao de Ordem de Servico" 2>/dev/null || true
	@awslocal s3 cp \
	  tech-challenge-notification-service/templates/ORDER_AWAITING_PAYMENT.html \
	  s3://$(NOTIFICATION_S3_BUCKET)/templates/ORDER_AWAITING_PAYMENT.html \
	  --metadata "subject=Pagamento Aguardado - Ordem de Servico" 2>/dev/null || true
	@echo "==> Templates carregados com sucesso!"

.PHONY: localstack-push-images
localstack-push-images: localstack-login-ecr
	@echo "==> Build + push das imagens para LocalStack ECR (opcional)..."
	cd tech-challenge-s1 && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-repo:$(IMAGE_TAG)
	cd tech-challenge-user-authentication && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG)
	cd tech-challenge-user-authorizer && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG)
	cd tech-challenge-notification-service && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG)
	cd tech-challenge-catalog-api && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-catalog-api-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-catalog-api-repo:$(IMAGE_TAG)

.PHONY: localstack-login-ecr
localstack-login-ecr:
	@echo "==> Login no LocalStack ECR..."
	@awslocal ecr get-login-password --region $(AWS_REGION) | \
	  docker login --username AWS --password-stdin $(DOCKER_REGISTRY) || \
	  echo "Aviso: falha no login ECR local, prosseguindo sem autenticação..."

.PHONY: localstack-down
localstack-down:
	@echo "==> Parando LocalStack (estado preservado)..."
	@docker compose -f docker-compose.localstack.yml down

.PHONY: localstack-clean
localstack-clean:
	@echo "==> Parando LocalStack e apagando volume local..."
	@docker compose -f docker-compose.localstack.yml down -v
	@rm -rf .localstack-volume
	@echo "==> LocalStack limpo. Rode 'make localstack-up-all' para recomeçar."

# =========================================================================================
# TARGETS AWS
# =========================================================================================

.PHONY: aws-deploy-all
aws-deploy-all: env-check
	@echo "==> Deploy completo na AWS..."
	@echo "==> Limpando repositórios ECR antigos..."
	-aws ecr delete-repository --repository-name tech-challenge-repo --force --region $(AWS_REGION) >/dev/null 2>&1 || true
	-aws ecr delete-repository --repository-name tech-challenge-user-authentication-repo --force --region $(AWS_REGION) >/dev/null 2>&1 || true
	-aws ecr delete-repository --repository-name tech-challenge-user-authorizer-repo --force --region $(AWS_REGION) >/dev/null 2>&1 || true
	-aws ecr delete-repository --repository-name tech-challenge-notification-service-repo --force --region $(AWS_REGION) >/dev/null 2>&1 || true
	-aws ecr delete-repository --repository-name tech-challenge-catalog-api-repo --force --region $(AWS_REGION) >/dev/null 2>&1 || true
	cd iac-tech-challenge-infra/aws && yes yes | terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && \
	  terraform apply -auto-approve -target=module.ecr_api -target=module.ecr_auth -target=module.ecr_authz -target=module.ecr_notif -target=module.ecr_catalog
	@$(MAKE) aws-push-images
	@$(MAKE) aws-tf-all

.PHONY: aws-push-images
aws-push-images: aws-login-ecr
	@echo "==> Build + push das imagens para AWS ECR..."
	cd tech-challenge-s1 && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-repo:$(IMAGE_TAG)
	cd tech-challenge-user-authentication && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-user-authentication-repo:$(IMAGE_TAG)
	cd tech-challenge-user-authorizer && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-user-authorizer-repo:$(IMAGE_TAG)
	cd tech-challenge-notification-service && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-notification-service-repo:$(IMAGE_TAG)
	cd tech-challenge-catalog-api && DOCKER_CONFIG=/tmp/.docker docker build --platform linux/amd64 -t $(DOCKER_REGISTRY)/tech-challenge-catalog-api-repo:$(IMAGE_TAG) .
	DOCKER_CONFIG=/tmp/.docker docker push $(DOCKER_REGISTRY)/tech-challenge-catalog-api-repo:$(IMAGE_TAG)

.PHONY: aws-login-ecr
aws-login-ecr:
	@echo "==> Login no AWS ECR..."
	@aws ecr get-login-password --region $(AWS_REGION) | \
	  docker login --username AWS --password-stdin $(DOCKER_REGISTRY)

.PHONY: aws-bootstrap
aws-bootstrap:
	@echo "==> Criando bucket de estado S3 AWS [$(S3_BUCKET)]..."
	@aws s3 mb s3://$(S3_BUCKET) --region $(AWS_REGION) 2>/dev/null || true

.PHONY: aws-tf-all
aws-tf-all: aws-bootstrap aws-tf-infra aws-tf-data aws-setup-k8s aws-tf-gateway
	@echo "==> Todas as camadas Terraform AWS aplicadas."
	@$(MAKE) aws-seed-admin

.PHONY: aws-tf-infra
aws-tf-infra:
	@echo "==> Aplicando Terraform: iac-tech-challenge-infra/aws..."
	cd iac-tech-challenge-infra/aws && \
	  yes yes | terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && \
	  terraform apply -auto-approve

.PHONY: aws-tf-data
aws-tf-data:
	@echo "==> Aplicando Terraform: iac-tech-challenge-data/aws..."
	cd iac-tech-challenge-data/aws && \
	  yes yes | terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && \
	  terraform apply -auto-approve

.PHONY: aws-tf-gateway
aws-tf-gateway:
	@echo "==> Aplicando Terraform: iac-tech-challenge-gateway/aws..."
	cd iac-tech-challenge-gateway/aws && \
	  yes yes | terraform init -reconfigure -backend-config="bucket=$(S3_BUCKET)" && \
	  terraform apply -auto-approve

.PHONY: aws-setup-k8s
aws-setup-k8s:
	@echo "==> Configurando addons EKS..."
	@aws eks update-kubeconfig --region $(AWS_REGION) --name $(EKS_CLUSTER_NAME) 2>/dev/null || true
	@kubectl apply -f iac-tech-challenge-infra/k8s/ 2>/dev/null || true

.PHONY: aws-seed-admin
aws-seed-admin:
	@echo "Seed manual para AWS não implementado via Makefile (requer acesso direto ao RDS via VPN)."

# =========================================================================================
# ALIASES DE COMPATIBILIDADE (mantém scripts antigos funcionando)
# =========================================================================================

.PHONY: deploy-all
deploy-all: aws-deploy-all

.PHONY: build-and-push-all
build-and-push-all: aws-push-images

.PHONY: terraform-apply-all
terraform-apply-all: aws-tf-all

.PHONY: login-ecr
login-ecr: aws-login-ecr

.PHONY: bootstrap-s3
bootstrap-s3: aws-bootstrap

.PHONY: setup-k8s-addons
setup-k8s-addons: aws-setup-k8s

.PHONY: seed-garagedb-admin
seed-garagedb-admin: localstack-seed-admin

.PHONY: localstack-up
localstack-up: localstack-start

# Mantido por compatibilidade — use 'make setup'
.PHONY: config
config: setup
