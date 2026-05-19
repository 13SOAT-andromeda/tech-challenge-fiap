# Guia de Gestão do Workspace (Git Submodules)

Este repositório atua como um **Orquestrador de Workspace**, utilizando Git Submodules para gerenciar múltiplos repositórios de microserviços e infraestrutura em um único lugar.

## 🚀 Primeiros Passos

### Clonando o Workspace pela primeira vez
Para garantir que você baixe o projeto raiz e todos os sub-repositórios de uma só vez:
```bash
git clone --recursive <url-deste-repositorio>
```

Se você já clonou mas as pastas dos módulos estão vazias:
```bash
git submodule update --init --recursive
```

---

## 🔄 Fluxo de Atualização

### Atualizar todos os repositórios recursivamente
Para puxar as últimas alterações de **todos** os submódulos de forma recursiva:
```bash
git submodule update --remote --merge
```
*Este comando entra em cada pasta, faz o fetch e tenta realizar o merge do branch remoto configurado.*

---

## 🏗️ Gestão de Módulos

### Adicionar um novo módulo
Siga as convenções de nomenclatura para manter o workspace organizado:

| Tipo de Projeto | Prefixo Sugerido | Exemplo |
| :--- | :--- | :--- |
| **API / Serviço** | `tech-challenge-` | `tech-challenge-payment-api` |
| **Infra / IaC** | `iac-tech-challenge-` | `iac-tech-challenge-db` |

**Comando:**
```bash
git submodule add -b main <URL_DO_REPOSITORIO> <NOME_DO_MODULO>
```

### Remover um módulo completamente
O Git requer alguns passos para limpar totalmente um submódulo:

1. Remova a entrada no Git e os arquivos:
   ```bash
   git rm -f <nome-do-modulo>
   ```
2. Remova os metadados internos (opcional, para limpeza profunda):
   ```bash
   rm -rf .git/modules/<nome-do-modulo>
   ```
3. Commit a remoção:
   ```bash
   git commit -m "chore: remove submodule <nome-do-modulo>"
   ```

---

## 🛠️ Desenvolvimento no Dia-a-Dia

### Como trabalhar em um módulo
Ao entrar em uma pasta de submódulo, o Git muitas vezes deixa você em estado "Detached HEAD". **Sempre mude para o branch principal antes de editar:**

```bash
cd <nome-do-modulo>
git checkout main
# ... faça suas alterações ...
git add .
git commit -m "feat: sua alteração"
git push origin main
```

### Sincronizando o Workspace Root
Após fazer um push dentro de um submódulo, você deve avisar o repositório "pai" que aquele módulo agora aponta para um novo commit:

```bash
cd .. # Volta para a raiz do workspace
git add <nome-do-modulo>
git commit -m "chore: atualiza ponteiro do modulo <nome-do-modulo>"
git push
```

---

## 🚀 Deployment e Orquestração

Este projeto utiliza um **Makefile** unificado para orquestrar o build das imagens Docker e a aplicação do Terraform em diferentes ambientes.

### 1. Configuração Inicial (Ambiente)
Antes de qualquer deploy, você precisa gerar o arquivo `.env` com as definições de target e credenciais:

```bash
make config
```
*   **Deploy Target:** Escolha `localstack` ou `aws`.
*   **LocalStack Auth Token:** Obrigatório para o modo `localstack` (LocalStack Pro).

---

### 💻 Deploy no LocalStack (Desenvolvimento Local)

Ideal para testes rápidos e validação de infraestrutura sem custos.

**Pré-requisitos:**
*   Docker e Docker Compose instalados.
*   WSL2 (se estiver no Windows).
*   Token do LocalStack Pro configurado via `make config`.

**Passo a Passo:**
1.  **Limpar ambiente anterior (recomendado):**
    ```bash
    docker compose -f docker-compose.localstack.yml down
    ```
2.  **Executar Deploy Completo:**
    ```bash
    make deploy-all
    ```
    *Este comando irá: subir o container LocalStack, criar os repositórios ECR, buildar as imagens de todos os microserviços, fazer o push e aplicar o Terraform (Infra, Data e Gateway).*

**Nota para WSL2:** O deploy utiliza o domínio `localhost.localstack.cloud` para evitar erros de resolução de host e permitir que o Docker trate o registro como seguro.

---

### ☁️ Deploy na AWS (Produção/Staging)

Utiliza os recursos reais da nuvem AWS.

**Pré-requisitos:**
*   AWS CLI configurado com credenciais válidas (ou através do `LabRole` da FIAP).
*   Permissões para gerenciar RDS, EKS, ECR e SQS.

**Passo a Passo:**
1.  **Configurar o Target:**
    Execute `make config` e selecione `aws`.
2.  **Executar Deploy Completo:**
    ```bash
    make deploy-all
    ```
    *No modo AWS, o Makefile fará o login no ECR real, buildará as imagens para plataforma linux/amd64 e aplicará o Terraform nas pastas `aws/` de cada módulo de infraestrutura.*

---

## 🔍 Resolução de Problemas (Troubleshooting)

### "O submódulo está como Detached HEAD"
**Causa:** Você atualizou o submódulo e ele apontou para um commit específico, não para um branch.
**Solução:** Entre na pasta e faça `git checkout main`.

### "Alterações não rastreadas no submódulo (content modified)"
**Causa:** Você esqueceu de fazer commit/push dentro do módulo antes de tentar atualizar o root.
**Solução:** Entre no módulo, resolva os arquivos pendentes (commit ou discard) e volte para a raiz.

### "Pasta do submódulo está vazia"
**Solução:** Execute `git submodule update --init --recursive`.
