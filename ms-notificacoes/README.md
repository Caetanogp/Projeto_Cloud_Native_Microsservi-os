# ms-notificacoes

**Responsável:** Matheus Brehm · **Stack:** Java 21 + Spring Boot 3.3 (Web, AMQP, Data MongoDB) · **Banco:** MongoDB 7 (`mongo-notificacoes`) · **Porta:** 8080

Consome os eventos `pedido.criado` do RabbitMQ, grava a notificação no MongoDB e confirma o pedido no `ms-pedidos` por REST.

## Endpoints

| Método | Rota | Descrição |
|---|---|---|
| GET | `/notificacoes` | Lista as notificações, da mais recente para a mais antiga |
| GET | `/notificacoes/pedido/{pedidoId}` | Notificação de um pedido (404 se não existir) |
| GET | `/health`, `/ready` | Probes de liveness e readiness (o `/ready` faz ping no MongoDB) |

## Consumo da fila

`PedidoCriadoListener` escuta a fila `pedidos.criados` e, para cada mensagem:

1. Grava a `Notificacao` no MongoDB. O índice único em `pedidoId` e a verificação prévia tornam o processamento idempotente.
2. Chama `PATCH http://ms-pedidos:8000/pedidos/{id}/status` com `{"status":"CONFIRMADO"}` (`PedidosClient`, `RestClient` com HTTP/1.1).
3. Se der erro, o Spring tenta 3 vezes (1 s, 2 s, 4 s limitado a 5 s) e a mensagem vai para a DLQ `pedidos.criados.dlq`, sem voltar para a fila.

A topologia (exchange, filas, DLQ) é declarada em `RabbitConfig` e precisa ser idêntica à de `ms-pedidos/app/messaging.py`.

## Configuração

Em `src/main/resources/application.yml`, com variáveis de ambiente: `MONGODB_URI`, `RABBITMQ_HOST`, `RABBITMQ_PORT`, `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `PEDIDOS_URL`, `POD_NAME`.

## Estrutura

```
src/main/java/br/edu/loja/notificacoes/
  NotificacoesApplication.java
  config/RabbitConfig.java              topologia AMQP e conversor JSON
  listener/PedidoCriadoListener.java    consumidor da fila
  client/PedidosClient.java             cliente REST do ms-pedidos
  model/                                Notificacao, PedidoCriadoEvent, NotificacaoRepository
  web/                                  NotificacoesController, PodInfo
k8s/                                    deployment.yaml, service.yaml, mongo.yaml, kustomization.yaml
```

## Rodar

```bash
docker compose up --build   # a partir da raiz do repositório; a API fica em http://localhost:8080/notificacoes
```

O build usa Maven dentro do Docker (Dockerfile multi-stage), então não precisa de Java 21 instalado.
