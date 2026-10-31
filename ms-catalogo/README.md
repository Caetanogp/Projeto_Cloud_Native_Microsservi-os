# ms-catalogo

**Responsável:** Caetano · **Stack:** Node.js 22 + Express + mysql2 · **Banco:** MySQL 8.4 (`mysql-catalogo`) · **Porta:** 3000

Cadastro de produtos e controle de estoque. É o serviço com **3 réplicas**: o Service `ms-catalogo` balanceia as requisições entre elas.

## Endpoints

| Método | Rota | Descrição |
|---|---|---|
| GET | `/produtos` | Lista os produtos |
| GET | `/produtos/{id}` | Busca um produto |
| POST | `/produtos` | Cria produto: `{"nome","preco","estoque"}` |
| POST | `/produtos/{id}/reservar` | Baixa o estoque de forma atômica: `{"quantidade":2}`. Responde 409 se o estoque for insuficiente. Chamado pelo ms-pedidos. |
| GET | `/health`, `/ready` | Probes de liveness e readiness |

Toda resposta traz o campo `pod` e o header `X-Pod-Name`.

## Como funciona

- Na subida, cria a tabela `produtos` e insere 5 produtos de exemplo (`INSERT IGNORE` com `UNIQUE(nome)`, seguro com várias réplicas iniciando juntas).
- A reserva usa `UPDATE ... SET estoque = estoque - ? WHERE id = ? AND estoque >= ?`, então duas réplicas nunca vendem o mesmo item duas vezes.
- Variáveis de ambiente: `PORT`, `POD_NAME`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`.

## Manifestos (`k8s/`)

`deployment.yaml` (3 réplicas, probes, Downward API), `service.yaml` (ClusterIP) e `mysql.yaml` (Secret, Service e StatefulSet com volume gp3).

## Rodar

```bash
docker compose up --build ms-catalogo      # a partir da raiz do repositório
curl http://localhost:8080/produtos        # com o gateway: docker compose up --build
```
