# ms-pedidos

**Responsável:** Davi Henrique · **Stack:** Python 3.12 + FastAPI + SQLAlchemy + httpx + pika · **Banco:** PostgreSQL 16 (`postgres-pedidos`) · **Porta:** 8000

Cria pedidos e orquestra o fluxo: valida o produto no catálogo (REST), grava no PostgreSQL e publica o evento no RabbitMQ.

## Endpoints

| Método | Rota | Descrição |
|---|---|---|
| POST | `/pedidos` | Cria pedido: `{"cliente","produto_id","quantidade"}` |
| GET | `/pedidos` | Lista os pedidos |
| GET | `/pedidos/{id}` | Busca um pedido |
| PATCH | `/pedidos/{id}/status` | Muda o status (`CRIADO`, `CONFIRMADO`, `CANCELADO`, `ERRO_PUBLICACAO`). Chamado pelo ms-notificacoes. |
| GET | `/health`, `/ready` | Probes de liveness e readiness |

Toda resposta traz o campo `pod` e o header `X-Pod-Name`. `POST /pedidos` traz também `catalogo_pod`, a réplica do catálogo que atendeu a chamada REST. A documentação interativa fica em `/docs` quando se acessa o serviço direto.

## Fluxo do `POST /pedidos`

1. **REST síncrono:** `POST http://ms-catalogo:3000/produtos/{id}/reservar`. Responde 404 se o produto não existir e 409 se o estoque for insuficiente.
2. **PostgreSQL:** grava o pedido com status `CRIADO`.
3. **RabbitMQ:** publica `pedido.criado` no exchange `pedidos`, com confirmação do broker e mensagem persistente. Se falhar, o pedido vira `ERRO_PUBLICACAO` e a API responde 502.

Mensagem publicada (JSON):

```json
{"pedidoId":1,"cliente":"Caetano","produtoId":1,"produtoNome":"Notebook Dell Inspiron","quantidade":2,"total":9199.8,"criadoEm":"2026-11-01T12:00:00+00:00","origemPod":"ms-pedidos-xxxxx"}
```

## Configuração

Variáveis de ambiente: `POD_NAME`, `CATALOGO_URL`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `RABBITMQ_HOST`, `RABBITMQ_PORT`, `RABBITMQ_USER`, `RABBITMQ_PASSWORD`. A topologia AMQP está em `app/config.py` e precisa ser idêntica à do `ms-notificacoes`.

## Estrutura

```
app/main.py        rotas FastAPI e fluxo do pedido
app/messaging.py   publicação no RabbitMQ (pika)
app/database.py    modelo SQLAlchemy e sessão
app/config.py      configuração por variáveis de ambiente
k8s/               deployment.yaml, service.yaml, postgres.yaml, kustomization.yaml
```

## Rodar

```bash
docker compose up --build   # a partir da raiz do repositório; a API fica em http://localhost:8080/pedidos
```
