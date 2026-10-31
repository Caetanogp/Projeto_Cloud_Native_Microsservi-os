#!/usr/bin/env bash
# Uso: ./scripts/build-push.sh <registry> [tag]
#   ECR:        ./scripts/build-push.sh 123456789012.dkr.ecr.us-east-1.amazonaws.com
#   Docker Hub: ./scripts/build-push.sh meuusuario
set -euo pipefail

REGISTRY="${1:?Informe o registry (ECR ou usuário do Docker Hub)}"
TAG="${2:-latest}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SERVICOS=(ms-catalogo ms-pedidos ms-notificacoes)

if [[ "$REGISTRY" == *.dkr.ecr.*.amazonaws.com ]]; then
  REGIAO="$(echo "$REGISTRY" | sed -E 's/.*\.dkr\.ecr\.([^.]+)\.amazonaws\.com/\1/')"
  echo "==> Login no ECR ($REGIAO)"
  aws ecr get-login-password --region "$REGIAO" | docker login --username AWS --password-stdin "$REGISTRY"
  for s in "${SERVICOS[@]}"; do
    aws ecr describe-repositories --repository-names "$s" --region "$REGIAO" >/dev/null 2>&1 \
      || aws ecr create-repository --repository-name "$s" --region "$REGIAO" >/dev/null
  done
fi

for s in "${SERVICOS[@]}"; do
  echo "==> Build e push de $s"
  docker build -t "$REGISTRY/$s:$TAG" "$RAIZ/$s"
  docker push "$REGISTRY/$s:$TAG"
done
echo "Imagens publicadas em $REGISTRY (tag $TAG)"
