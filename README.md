# Loja Cloud Native — Avaliação N2

Aplicação de loja com três microsserviços, implantada no Amazon EKS. Cada integrante da equipe é dono de um serviço, com linguagem e banco próprios.

| Serviço | Responsável | Stack | Banco |
|---|---|---|---|
| [ms-catalogo](ms-catalogo/) | Caetano | Node.js 22 + Express | MySQL 8.4 |
| [ms-pedidos](ms-pedidos/) | Davi Henrique | Python 3.12 + FastAPI | PostgreSQL 16 |
| [ms-notificacoes](ms-notificacoes/) | Matheus Brehm | Java 21 + Spring Boot 3 | MongoDB 7 |

Mensageria: RabbitMQ. Entrada externa: NGINX Ingress Controller.

## Fluxo

1. `POST /pedidos` entra pelo Ingress e chega ao `ms-pedidos`.
2. O `ms-pedidos` reserva o estoque no `ms-catalogo` por REST, usando `http://ms-catalogo:3000` (Service Discovery). As 3 réplicas do catálogo se revezam.
3. O `ms-pedidos` grava o pedido no PostgreSQL e publica `pedido.criado` no RabbitMQ.
4. O `ms-notificacoes` consome a mensagem e grava a notificação no MongoDB.
5. O `ms-notificacoes` chama `PATCH /pedidos/{id}/status` e o pedido passa a `CONFIRMADO`.

## Rotas externas

| Rota | Serviço |
|---|---|
| `GET/POST /produtos`, `GET /produtos/{id}`, `POST /produtos/{id}/reservar` | ms-catalogo (3 réplicas) |
| `POST/GET /pedidos`, `GET /pedidos/{id}`, `PATCH /pedidos/{id}/status` | ms-pedidos |
| `GET /notificacoes`, `GET /notificacoes/pedido/{id}` | ms-notificacoes |

Toda resposta traz o campo `pod`, com o Pod que atendeu a requisição.

## Rodar localmente (Docker Desktop)

```bash
docker compose up --build
./scripts/demo.sh http://localhost:8080          # PowerShell: .\scripts\demo.ps1
docker compose up --build --scale ms-catalogo=3  # para ver o balanceamento localmente
```

Painel do RabbitMQ: http://localhost:15672 (usuário `loja`, senha `loja123`).

## Deploy no Amazon EKS

Passo a passo em [docs/deploy-eks.md](docs/deploy-eks.md). Resumo:

```bash
eksctl create cluster -f infra/eks/cluster.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/aws/deploy.yaml
./scripts/build-push.sh <registry>
./scripts/deploy.sh <registry>
./scripts/demo.sh http://<hostname-do-elb>
```

## Documentação

- [docs/arquitetura.md](docs/arquitetura.md): arquitetura e mapa requisito → evidência
- [docs/deploy-eks.md](docs/deploy-eks.md): criação do cluster e deploy
- [docs/roteiro-apresentacao.md](docs/roteiro-apresentacao.md): roteiro da demonstração em sala

