# Roteiro da apresentação

Tempo sugerido: 12 a 15 minutos. Deixe tudo implantado e testado antes de entrar na sala, com um terminal para o `kubectl` e outro para os `curl`.

Antes de começar:

```bash
export HOST=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $HOST
```

## 1. Arquitetura e responsabilidades (todos, 2 min)

Mostre o diagrama de [arquitetura.md](arquitetura.md). Cada integrante diz em uma frase o que o seu serviço faz.

## 2. Microsserviços no EKS (Caetano, 1 min) — R2

```bash
kubectl get nodes
kubectl get deploy,pods,svc,ingress -n loja -o wide
```

Aponte: 3 Pods do `ms-catalogo`, os Services `ClusterIP`, o Ingress e os 3 StatefulSets de banco.

## 3. Linguagens e bancos (1 min) — R1

| Serviço | Linguagem | Banco |
|---|---|---|
| ms-catalogo | Node.js | MySQL |
| ms-pedidos | Python | PostgreSQL |
| ms-notificacoes | Java | MongoDB |

## 4. Isolamento da persistência (1 min) — R1

```bash
kubectl get statefulset,pvc,secret -n loja
kubectl get deploy ms-catalogo -n loja -o jsonpath='{.spec.template.spec.containers[0].env[*].name}'
```

Cada banco tem o seu StatefulSet, o seu volume e o seu Secret. O `ms-catalogo` só recebe as variáveis do MySQL, e os outros serviços não têm as credenciais dele.

## 5. Acesso externo pelo Ingress (1 min) — R2

```bash
kubectl get ingress -n loja
curl http://$HOST/produtos
curl http://$HOST/pedidos
curl http://$HOST/notificacoes
```

Mostre [k8s/ingress.yaml](../k8s/ingress.yaml): três regras, cada uma para um Service.

## 6. Service Discovery (1 min) — R2

```bash
kubectl exec -n loja deploy/ms-pedidos -- python -c "import socket; print(socket.gethostbyname('ms-catalogo'))"
kubectl get pods -n loja -l app=ms-catalogo -o wide     # os IPs dos Pods são outros
kubectl get deploy ms-pedidos -n loja -o jsonpath='{.spec.template.spec.containers[0].env}'
```

Aponte `CATALOGO_URL=http://ms-catalogo:3000` e `RABBITMQ_HOST=rabbitmq`: o código nunca usa IP de Pod.

## 7. Escalabilidade e balanceamento (Caetano, 2 min) — R2

```bash
for i in $(seq 1 12); do curl -s http://$HOST/produtos | grep -o '"pod":"[^"]*"' | head -1; done | sort | uniq -c
```

O campo `pod` alterna entre as 3 réplicas. Se quiser mostrar a escala ao vivo:

```bash
kubectl scale -n loja deploy/ms-catalogo --replicas=5
kubectl get pods -n loja -l app=ms-catalogo -w
kubectl scale -n loja deploy/ms-catalogo --replicas=3
```

## 8. Fluxo integrado REST + RabbitMQ (Davi e Matheus, 4 min) — R3

Em um terminal, deixe os logs abertos:

```bash
kubectl logs -n loja deploy/ms-pedidos -f &
kubectl logs -n loja deploy/ms-notificacoes -f &
```

Rode a demonstração completa:

```bash
./scripts/demo.sh http://$HOST
```

Ou passo a passo:

```bash
curl -s -X POST http://$HOST/pedidos -H 'Content-Type: application/json' \
  -d '{"cliente":"Maria","produto_id":2,"quantidade":1}'
curl -s http://$HOST/pedidos/<id>              # status CONFIRMADO
curl -s http://$HOST/notificacoes/pedido/<id>  # notificação gravada no MongoDB
curl -s http://$HOST/produtos/2                # estoque reduzido
```

Explique a sequência:

1. `ms-pedidos` chamou o catálogo por REST. O `catalogo_pod` da resposta mostra qual réplica atendeu.
2. `ms-pedidos` gravou no PostgreSQL e publicou `pedido.criado`.
3. `ms-notificacoes` consumiu, gravou no MongoDB e chamou `PATCH /pedidos/{id}/status`.
4. O pedido passou de `CRIADO` para `CONFIRMADO`.

Para mostrar o broker:

```bash
kubectl port-forward -n loja svc/rabbitmq 15672:15672
# http://localhost:15672 (loja / loja123): exchange "pedidos", fila "pedidos.criados" e a DLQ
```

## 9. Perguntas que podem aparecer

- **Por que o RabbitMQ e não só REST?** O pedido não depende de o `ms-notificacoes` estar no ar: a mensagem fica na fila e é processada quando ele voltar.
- **E se o consumidor falhar?** Três tentativas e depois a mensagem vai para a DLQ `pedidos.criados.dlq`.
- **Como as réplicas não vendem o mesmo estoque duas vezes?** O `UPDATE ... WHERE estoque >= ?` é atômico no MySQL.
- **Por que `/health` e `/ready` separados?** Liveness não depende do banco, para um banco fora do ar não causar reinício em loop. Readiness depende, para o Pod sair do Service.
- **Os bancos perdem dados se o Pod reiniciar?** Não: StatefulSet com PVC de volume EBS gp3.
