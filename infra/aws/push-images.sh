#!/bin/bash
# Builda as 3 imagens do CollabDocs para linux/amd64 e publica nos
# repositorios ECR criados pelo Terraform (infra/aws/terraform).
#
# Uso: ./infra/aws/push-images.sh
# Pre-requisitos: terraform apply ja rodado, aws cli configurado, docker buildx.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

region="$(terraform -chdir="$TF_DIR" output -raw aws_region)"
java_repo="$(terraform -chdir="$TF_DIR" output -json ecr_repository_urls | jq -r .java_backend)"
go_repo="$(terraform -chdir="$TF_DIR" output -json ecr_repository_urls | jq -r .go_collab)"
frontend_repo="$(terraform -chdir="$TF_DIR" output -json ecr_repository_urls | jq -r .frontend)"

registry="${java_repo%%/*}"

echo "==> Autenticando no ECR ($registry)"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"

echo "==> Build + push java-backend"
docker buildx build --platform linux/amd64 -t "$java_repo:latest" "$REPO_ROOT/java/backend" --push

echo "==> Build + push go-collab"
docker buildx build --platform linux/amd64 -t "$go_repo:latest" "$REPO_ROOT/go/collab-service" --push

echo "==> Build + push frontend"
docker buildx build --platform linux/amd64 -t "$frontend_repo:latest" "$REPO_ROOT/frontend" --push

echo "==> Concluido. As instancias EC2 vao puxar as novas imagens no proximo retry do systemd (ate ~15s)."
echo "    Para forcar agora: ssh na instancia e rodar 'sudo systemctl restart collabdocs.service'"
