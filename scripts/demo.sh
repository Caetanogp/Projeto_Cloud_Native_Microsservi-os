#!/usr/bin/env bash
# Demonstração do fluxo completo pelo Ingress (ou pelo gateway local do Docker Compose).
# Uso: ./scripts/demo.sh http://<hostname-do-elb>      (local: http://localhost:8080)
set -euo pipefail

BASE="${1:-http://localhost:8080}"
BASE="${BASE%/}"

titulo() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }

titulo "1) Ingress: GET $BASE/produtos"
curl -s "$BASE/produtos"; echo

titulo "2) Balanceamento: 12 chamadas a GET /produtos (campo \"pod\" da resposta)"
for _ in $(seq 1 12); do
  curl -s "$BASE/produtos" | grep -o '"pod":"[^"]*"' | head -1
done | sort | uniq -c

titulo "3) Fluxo integrado: POST /pedidos (REST ao catálogo + publicação no RabbitMQ)"
RESPOSTA="$(curl -s -X POST "$BASE/pedidos" -H 'Content-Type: application/json' \
  -d '{"cliente":"Caetano","produto_id":1,"quantidade":2}')"
echo "$RESPOSTA"
ID="$(echo "$RESPOSTA" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)"
if [[ -z "$ID" ]]; then echo "Pedido não foi criado."; exit 1; fi
echo "-> catalogo_pod mostra qual réplica do catálogo atendeu a chamada REST do ms-pedidos"

titulo "4) Aguardando o ms-notificacoes consumir a mensagem..."
STATUS=""
for _ in $(seq 1 15); do
  STATUS="$(curl -s "$BASE/pedidos/$ID" | grep -o '"status":"[^"]*"' | head -1)"
  [[ "$STATUS" == '"status":"CONFIRMADO"' ]] && break
  sleep 1
done
curl -s "$BASE/pedidos/$ID"; echo
echo "-> status final: $STATUS"

titulo "5) Notificação gravada no MongoDB pelo ms-notificacoes"
curl -s "$BASE/notificacoes/pedido/$ID"; echo

titulo "6) Estoque do produto 1 depois da reserva"
curl -s "$BASE/produtos/1"; echo

if [[ "$STATUS" == '"status":"CONFIRMADO"' ]]; then
  printf '\n\033[1;32mFluxo OK: REST + RabbitMQ funcionando.\033[0m\n'
else
  printf '\n\033[1;31mPedido não foi confirmado. Veja os logs dos serviços.\033[0m\n'
  exit 1
fi
