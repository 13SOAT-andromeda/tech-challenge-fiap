# Plano de Implementação LocalStack PRO

## Objetivo
Criar a infraestrutura local completa baseada na engenharia reversa das pastas `localstack/` dos submódulos, utilizando a licença PRO (Estudante) do usuário, Docker Compose e scripts de inicialização (Bootstrapping).

## Descobertas da Engenharia Reversa
1. **Estado do Terraform Local:** Configurado para o bucket S3 `tech-challenge-bucket-andromeda-local` via endpoint local (`http://localhost:4566`).
2. **Serviços PRO Identificados:** EKS e RDS estão configurados nos arquivos `.tf`, o que exige estritamente a imagem `localstack/localstack-pro` e a injeção do `LOCALSTACK_AUTH_TOKEN`.
3. **Mocks de Lambda:** As lambdas locais (authentication, authorizer, notification) foram configuradas no repositório para usar um `dummy.zip` em vez das imagens ECR reais. A infraestrutura local as trata como "stubs" para criar o API Gateway.

## Passo a Passo

### Passo 1: Criar o `docker-compose.localstack.yml`
```yaml
version: "3.8"

services:
  localstack:
    container_name: "tech-challenge-localstack"
    image: localstack/localstack-pro:latest
    ports:
      - "127.0.0.1:4566:4566"            # LocalStack Gateway
      - "127.0.0.1:4510-4559:4510-4559"  # Portas de serviços externos
      - "127.0.0.1:443:443"              # HTTPS (Pro)
    environment:
      - LOCALSTACK_AUTH_TOKEN=${LOCALSTACK_AUTH_TOKEN:?}
      - DEBUG=1
      - PERSISTENCE=1 # Mantém o estado mesmo que o container reinicie
      - DOCKER_HOST=unix:///var/run/docker.sock
    volumes:
      - "./.localstack-volume:/var/lib/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./localstack-init.sh:/etc/localstack/init/ready.d/init-aws.sh"
```

### Passo 2: Criar o Script `localstack-init.sh`
Para inicializar os recursos cruciais (S3 Backend) assim que o LocalStack ficar `ready`:
```bash
#!/bin/bash
echo "🚀 Inicializando Recursos Base do LocalStack (Bootstrapping)"
BUCKET_NAME="tech-challenge-bucket-andromeda-local"
REGION="us-east-1"
awslocal s3 mb s3://$BUCKET_NAME --region $REGION
echo "✅ Bucket $BUCKET_NAME criado e pronto para o Terraform."
```

### Passo 3: Criar um Target `dummy.zip`
Como o Terraform dos módulos locais requer um arquivo `dummy.zip` (ausente no repositório):
Criaremos um arquivo zip vazio `iac-tech-challenge-infra/localstack/dummy.zip` para evitar erros durante o `terraform apply`.

### Passo 4: Atualizar o `Makefile`
Adicionar comandos de orquestração para a infra local:
- `make localstack-up`: Sobe o docker-compose.
- `make localstack-deploy`: Roda a aplicação sequencial do Terraform apontando para o LocalStack.
