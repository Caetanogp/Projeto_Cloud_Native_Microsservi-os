#!/usr/bin/env bash
# Uso: ./scripts/deploy.sh <registry> [tag]
# Renderiza o kustomize, troca as imagens locais pelas do registry e aplica no cluster atual.
set -euo pipefail

REGISTRY="${1:?Informe o registry usado no build-push}"
TAG="${2:-latest}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Aplicando manifestos no cluster: $(kubectl config current-context)"
kubectl kustomize "$RAIZ/k8s" \
  | sed -E "s#image: (ms-catalogo|ms-pedidos|ms-notificacoes):latest#image: $REGISTRY/\1:$TAG#" \
  | kubectl apply -f -

echo "==> Aguardando os bancos e o RabbitMQ"
kubectl -n loja rollout status statefulset/mysql-catalogo --timeout=300s
kubectl -n loja rollout status statefulset/postgres-pedidos --timeout=300s
kubectl -n loja rollout status statefulset/mongo-notificacoes --timeout=300s
kubectl -n loja rollout status deployment/rabbitmq --timeout=300s

echo "==> Aguardando os microsserviços"
for d in ms-catalogo ms-pedidos ms-notificacoes; do
  kubectl -n loja rollout status "deployment/$d" --timeout=300s
done

kubectl -n loja get pods,svc,ingress -o wide
echo
echo "Hostname do Ingress (pode levar alguns minutos para resolver no DNS):"
kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo
