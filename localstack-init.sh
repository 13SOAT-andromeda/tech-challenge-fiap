#!/bin/bash
# Este script é executado automaticamente pelo LocalStack quando ele fica pronto (ready.d).

echo "=========================================================="
echo "🚀 Inicializando Recursos Base do LocalStack (Bootstrapping)"
echo "=========================================================="

BUCKET_NAME="tech-challenge-bucket-andromeda-local"
REGION="us-east-1"

echo "==> Criando S3 Bucket para o Terraform State ($BUCKET_NAME)..."
awslocal s3 mb s3://$BUCKET_NAME --region $REGION

# Verifica se foi criado com sucesso
if awslocal s3 ls "s3://$BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
  echo "❌ Falha ao criar o bucket."
else
  echo "✅ Bucket $BUCKET_NAME criado e pronto para o Terraform."
fi

echo "=========================================================="
echo "🎯 LocalStack pronto para receber o deploy!"
echo "=========================================================="
