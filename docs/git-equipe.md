# Git da equipe

O repositório é um monorepo. Cada integrante comita **a própria pasta**, com a própria conta, para a participação de cada um ficar identificável no histórico. Os commits e o push são feitos à mão por cada integrante.

| Integrante | Comita | Quando |
|---|---|---|
| Caetano | tudo que não é `ms-pedidos/` nem `ms-notificacoes/`: `README.md`, `docs/`, `infra/`, `k8s/`, `docker/`, `scripts/`, `docker-compose.yml`, `.gitignore`, `.gitattributes` e `ms-catalogo/` | primeiro, para criar o repositório |
| Davi | `ms-pedidos/` | depois do push do Caetano |
| Matheus | `ms-notificacoes/` | depois do push do Caetano |

## 1. Caetano: criar o repositório e dar o primeiro push

```bash
git init -b main
git add README.md .gitignore .gitattributes docker-compose.yml docs infra k8s docker scripts ms-catalogo
git status                       # confira que ms-pedidos/ e ms-notificacoes/ não entraram
git commit -m "Infra compartilhada e ms-catalogo (Node + MySQL)"
git remote add origin https://github.com/<usuario>/<repositorio>.git
git push -u origin main
```

Depois, no GitHub: **Settings → Collaborators** e adicione o Davi e o Matheus com permissão de escrita.

## 2. Davi e Matheus: clonar e comitar a própria pasta

```bash
git clone https://github.com/<usuario>/<repositorio>.git
cd <repositorio>
git config user.name  "Seu Nome"          # confira também: git config user.email
git config user.email "seu-email@exemplo.com"
```

Copie a pasta do seu serviço (recebida do Caetano) para dentro do clone: `ms-pedidos/` para o Davi, `ms-notificacoes/` para o Matheus. Depois:

```bash
# Davi
git add ms-pedidos
git commit -m "ms-pedidos: FastAPI + PostgreSQL + publicação no RabbitMQ"
git push origin main

# Matheus
git add ms-notificacoes
git commit -m "ms-notificacoes: Spring Boot + MongoDB + consumo do RabbitMQ"
git push origin main
```

Se o `push` for recusado porque o outro integrante já enviou algo, rode `git pull --rebase origin main` e envie de novo. As pastas são diferentes, então não há conflito.

Se preferirem trabalhar com branches e Pull Requests, crie `git checkout -b ms-pedidos` (ou `ms-notificacoes`), faça o push da branch e abra o PR no GitHub.

## 3. Conferir antes da apresentação

```bash
git log --format='%h %an %s' --name-only   # cada autor aparece nos arquivos do seu serviço
```

Cada integrante precisa saber explicar o código da sua pasta e como ele se integra aos outros.
