# Arquitetura

## Visão geral

```
                          CLIENTE / BROWSER
                                 |
                                 v
                            AMAZON AWS (ELB)
                                 |
                                 v
                            AMAZON EKS
                                 |
                                 v
                      NGINX Ingress Controller
                                 |
                  Regras de Ingress (/produtos, /pedidos, /notificacoes)
                                 |
        +------------------------+-------------------------+
        |                        |                         |
        v                        v                         v
  Service ms-catalogo     Service ms-pedidos      Service ms-notificacoes
     ClusterIP :3000         ClusterIP :8000          ClusterIP :8080
        |                        |                         ^
        v                        |  REST (síncrono)        |
  Pods ms-catalogo  <------------+                         |
   (3 réplicas)                  |                         |
        |                        | AMQP (assíncrono)       |
        v                        v                         |
  Service mysql-catalogo   Service rabbitmq  ---------------+
        |                        |                         |
        v                        |                         v
  MySQL (Banco A)                |            Service mongo-notificacoes
                                 |                         |
  Service postgres-pedidos <-----+                         v
        |                                          MongoDB (Banco C)
        v
  PostgreSQL (Banco B)

  ms-notificacoes --REST PATCH--> ms-pedidos   (confirma o pedido depois de processar a mensagem)
```

Tudo roda no namespace `loja`.

## Microsserviços

| Serviço | Responsabilidade | Dono |
|---|---|---|
| ms-catalogo | Cadastro de produtos e controle de estoque. Reserva estoque de forma atômica. | Caetano |
| ms-pedidos | Cria pedidos. Valida produto e estoque no catálogo (REST), grava no PostgreSQL e publica o evento `pedido.criado`. Recebe a confirmação de status. | Davi |
| ms-notificacoes | Consome `pedido.criado`, grava a notificação no MongoDB e confirma o pedido no ms-pedidos (REST). | Matheus |

## RabbitMQ

| Item | Valor |
|---|---|
| Exchange | `pedidos` (topic, durável) |
| Routing key | `pedido.criado` |
| Fila | `pedidos.criados` (durável) |
| Dead letter | exchange `pedidos.dlx`, fila `pedidos.criados.dlq`, routing key `pedido.falhou` |
| Produtor | ms-pedidos (`pika`, com publisher confirms e mensagem persistente) |
| Consumidor | ms-notificacoes (`@RabbitListener`, 3 tentativas e depois DLQ) |

O produtor e o consumidor declaram a mesma topologia. Os argumentos precisam ser idênticos, senão o RabbitMQ recusa a declaração.

## Mapa requisito → evidência

| Requisito | Onde está no projeto | Como mostrar |
|---|---|---|
| Um microsserviço por integrante | `ms-catalogo/`, `ms-pedidos/`, `ms-notificacoes/` | Cada um apresenta o seu código e `k8s/` |
| 2+ linguagens e 2+ bancos | Node, Python e Java; MySQL, PostgreSQL e MongoDB | `kubectl get pods -n loja`, `docker image ls` |
| Docker | `Dockerfile` em cada serviço | Imagens no registry (ECR ou Docker Hub) |
| Amazon EKS com Deployments, Pods e Services | `*/k8s/deployment.yaml`, `service.yaml` | `kubectl get nodes,deploy,pods,svc -n loja -o wide` |
| Database per Service | `*/k8s/mysql.yaml`, `postgres.yaml`, `mongo.yaml`, cada um com Secret próprio | `kubectl get secret,statefulset,pvc -n loja` |
| REST síncrono | ms-pedidos → `POST ms-catalogo/produtos/{id}/reservar` e ms-notificacoes → `PATCH ms-pedidos/pedidos/{id}/status` | Campo `catalogo_pod` e logs |
| RabbitMQ | `ms-pedidos/app/messaging.py` e `ms-notificacoes/.../PedidoCriadoListener.java` | Painel do RabbitMQ, logs e pedido `CONFIRMADO` |
| Service Discovery | Variáveis `CATALOGO_URL`, `PEDIDOS_URL`, `DB_HOST`, `RABBITMQ_HOST` com nomes de Service | `kubectl exec ... -- nslookup ms-catalogo` |
| Escalabilidade horizontal | `ms-catalogo/k8s/deployment.yaml` com `replicas: 3` | 12 chamadas a `/produtos` com o campo `pod` alternando |
| Ingress NGINX | `k8s/ingress.yaml` | `kubectl get ingress -n loja` e chamadas ao hostname do ELB |

## Decisões

- **Sem rewrite no Ingress.** Cada serviço serve a própria coleção (`/produtos`, `/pedidos`, `/notificacoes`), então o roteamento é só por prefixo de path.
- **Probes separadas.** `/health` (liveness) só diz que o processo está vivo. `/ready` (readiness) confere o banco. Assim, um banco fora do ar tira o Pod do Service, mas não derruba o Pod em loop.
- **Estoque atômico.** O catálogo faz `UPDATE ... SET estoque = estoque - ? WHERE id = ? AND estoque >= ?`, sem condição de corrida entre as 3 réplicas.
- **Idempotência.** Índice único em `pedidoId` no MongoDB, para uma mensagem reentregue não duplicar a notificação.
- **Bancos em StatefulSet com volume EBS gp3.** Os dados sobrevivem à reinicialização do Pod. O `subPath` evita o diretório `lost+found` do volume.
- **Credenciais em Secrets separados por banco.** Só o serviço dono recebe o Secret do seu banco. Os valores do repositório são de laboratório e não servem para produção.
- **Falha na publicação.** Se o RabbitMQ estiver fora, o pedido fica salvo com status `ERRO_PUBLICACAO` e a API responde 502.
