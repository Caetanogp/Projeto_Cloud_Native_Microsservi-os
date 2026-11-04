# Deploy no Amazon EKS

Procedimento validado no **AWS Academy Learner Lab** (Kubernetes 1.34, `us-east-1`, 2 nós `t3.medium`, imagens no ECR). O sistema inteiro subiu e a demonstração (`scripts/demo`) passou pelo load balancer da AWS. O caminho A (conta própria, com `eksctl`) está no fim e **não foi testado**.

## Resumo rápido

```powershell
# 1. Start Lab no AWS Academy, cole as credenciais em %USERPROFILE%\.aws\credentials
# 2. Publique as imagens no ECR (só na primeira vez; elas ficam guardadas)
.\scripts\build-push.ps1 -Registry <conta>.dkr.ecr.us-east-1.amazonaws.com
# 3. Cria cluster, nós, volumes, NGINX Ingress e a aplicação (25 a 30 minutos)
.\scripts\eks-criar.ps1
# 4. Testa
.\scripts\demo.ps1 -BaseUrl http://<hostname-do-elb>
# 5. Ao terminar, apaga tudo
.\scripts\eks-apagar.ps1
```

`<conta>` é o `AWSAccountId` que aparece em **AWS Details** (ou `aws sts get-caller-identity --query Account --output text`).

## 1. Pré-requisitos

- **AWS CLI v2.** Baixe o instalador oficial em `https://awscli.amazonaws.com/AWSCLIV2.msi` (a assinatura digital é da Amazon Web Services, Inc.) e instale. Abra um PowerShell **novo** e confira com `aws --version`.
- **kubectl** e **Docker Desktop** (aberto, para o `build-push`).
- Nos comandos `kubectl` com `-o jsonpath`, use o **Git Bash**. As aspas do PowerShell 5.1 quebram esses comandos.

## 2. Entrar no Learner Lab e configurar as credenciais

1. No Canvas da disciplina de Cloud, abra o item do AWS Academy Learner Lab. Se o login automático falhar, use **Student Login** em `awsacademy.com` com a conta criada pelo convite do professor.
2. Em **Módulos → Iniciar os laboratórios de aprendizagem da AWS Academy**, clique em **Start Lab** e espere a bolinha ao lado de **AWS** ficar **verde**.
3. Clique em **AWS Details**, depois em **Show** ao lado de **AWS CLI**, e copie o bloco inteiro (começa com `[default]`).
4. Cole em `C:\Users\<voce>\.aws\credentials`. **O arquivo não pode ter extensão**: o Bloco de Notas costuma salvar como `credentials.txt`, e aí o CLI não o encontra.
5. Crie `C:\Users\<voce>\.aws\config` com:
   ```
   [default]
   region = us-east-1
   output = json
   ```
6. Teste: `aws sts get-caller-identity`. Deve mostrar a conta e o papel `voclabs`.

**Não cole essas credenciais em chats nem em prints.** Elas expiram quando a sessão acaba (4 horas), e a cada novo Start Lab você copia um bloco novo.

## 3. Publicar as imagens no ECR

```powershell
.\scripts\build-push.ps1 -Registry <conta>.dkr.ecr.us-east-1.amazonaws.com
```

O script faz login no ECR, cria os repositórios que faltarem, e faz build e push das 3 imagens. As imagens **continuam no ECR** entre sessões e depois que o cluster é apagado, então esse passo só precisa ser refeito se o código mudar.

## 4. Criar o cluster e implantar

```powershell
.\scripts\eks-criar.ps1
```

O que ele faz, na ordem:

1. Confere as credenciais e se as 3 imagens estão no ECR.
2. Cria o cluster `loja-cloud-native` (Kubernetes 1.34, função **LabRole**, endpoint público e privado, modo automático desligado). 10 a 15 minutos.
3. Cria o grupo de nós `ng-loja` (2 × `t3.medium`, máximo 3, função **LabRole**, Amazon Linux 2023). 3 a 5 minutos.
4. Instala os complementos `aws-ebs-csi-driver` e `metrics-server`. CoreDNS, kube-proxy e VPC CNI já vêm com o cluster.
5. **Sobe o limite de saltos do IMDS para 2** nas instâncias (veja abaixo).
6. Conecta o `kubectl` e espera o driver de volumes ficar disponível.
7. Instala o NGINX Ingress Controller `controller-v1.12.1`.
8. Chama o `deploy.ps1`: bancos (StatefulSets com volumes gp3), RabbitMQ, os 3 microsserviços e o Ingress.

No fim, o `deploy.ps1` mostra o hostname do load balancer. O DNS dele costuma resolver em poucos segundos.

### Por que o ajuste do IMDS (limite de saltos 2)

Nos nós novos do EKS, os Pods não alcançam o serviço de metadados da instância (limite de saltos 1). O driver EBS CSI não pega as credenciais e fica em `Error`, com a mensagem `no EC2 IMDS role found ... context deadline exceeded`. Os volumes dos bancos nunca são criados e os Pods dos bancos ficam `Pending`.

O ajuste resolve na hora, sem reiniciar nada. **Contrapartida de segurança:** qualquer Pod do cluster passa a poder ler as credenciais da instância. No laboratório, com só os nossos Pods e um cluster descartável, o risco prático é baixo. Em produção, o correto seria Identidade de Pods ou IRSA. Se as instâncias forem recriadas, o ajuste se perde e precisa ser refeito.

Alternativa sem mexer em segurança: trocar `storageClassName: gp3` por `emptyDir` nos arquivos `*/k8s/mysql.yaml`, `postgres.yaml` e `mongo.yaml`. Funciona, mas os dados somem se o Pod do banco reiniciar.

## 5. Testar

```bash
HOST=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
./scripts/demo.sh http://$HOST        # Git Bash; no PowerShell: .\scripts\demo.ps1 -BaseUrl http://<hostname>
```

Comandos úteis (Git Bash):

```bash
kubectl get nodes,deploy,statefulset,pods,svc,ingress,pvc -n loja -o wide
kubectl logs -n loja deploy/ms-pedidos
kubectl logs -n loja deploy/ms-notificacoes
kubectl exec -n loja deploy/rabbitmq -- rabbitmqctl list_queues name messages consumers
kubectl exec -n loja deploy/ms-pedidos -- python -c "import socket; print(socket.gethostbyname('ms-catalogo'))"
kubectl scale -n loja deploy/ms-catalogo --replicas=5     # e depois de volta para 3
```

Os dados da demonstração ficam nos bancos. Para recomeçar do zero, sem recriar o cluster:

```bash
kubectl exec -n loja postgres-pedidos-0 -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "TRUNCATE pedidos RESTART IDENTITY"'
kubectl exec -n loja mongo-notificacoes-0 -- sh -c 'mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin notificacoes --eval "db.notificacoes.deleteMany({})"'
kubectl exec -n loja mysql-catalogo-0 -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" catalogo -e "UPDATE produtos SET estoque = CASE id WHEN 1 THEN 25 WHEN 2 THEN 80 WHEN 3 THEN 40 WHEN 4 THEN 15 WHEN 5 THEN 60 END WHERE id BETWEEN 1 AND 5"'
```

## 6. Sessão de 4 horas e orçamento

- O laboratório tem orçamento de **US$ 50**, e o contador **Used $X of $50** atrasa várias horas. Não dá para confiar nele para saber quanto sobrou.
- Cada sessão dura 4 horas. Ao fim dela a AWS encerra as instâncias EC2 (os nós). O comportamento do cluster depois disso **não foi testado**: o grupo de nós pode recriar as máquinas, e as novas voltariam com o IMDS em 1.
- O cluster ligado custa cerca de US$ 0,20 a 0,25 por hora (estimativa com preços de referência), e o load balancer continua cobrando entre sessões.
- **Recomendação:** criar o cluster perto da apresentação (por exemplo na véspera), testar e apagar logo depois. Antes de apresentar, clique em **Start Lab** de novo para reiniciar o relógio, cole as credenciais novas, e confira que tudo está `Running`.

## 7. Apagar tudo

```powershell
.\scripts\eks-apagar.ps1              # mantém as imagens no ECR (custam centavos)
.\scripts\eks-apagar.ps1 -ApagarECR   # depois da apresentação, remove também as imagens
```

Ordem: namespace `loja` (e os volumes) → NGINX Ingress (e o load balancer) → grupo de nós → cluster. No fim ele imprime uma verificação, e tudo deve estar em **0**.

## 8. Problemas comuns

| Sintoma | Causa e solução |
|---|---|
| `Unable to locate credentials` | O arquivo `credentials` não existe ou tem `.txt` no nome. Confira com `dir $env:USERPROFILE\.aws`. |
| `ExpiredToken` ou `InvalidClientTokenId` | A sessão expirou. Start Lab de novo e cole as credenciais novas. |
| `docker login` no ECR dá `400 Bad Request` | O pipe do PowerShell 5.1 corrompe a senha. O `build-push.ps1` já usa `cmd /c` para evitar isso. |
| `kubectl` diz `executable aws not found` | O `aws` não está no PATH daquele terminal. Abra um terminal novo depois de instalar o AWS CLI. |
| Pods dos bancos `Pending`, PVC `Pending` | O driver EBS CSI está com erro. Veja `kubectl logs -n kube-system -l app=ebs-csi-controller -c ebs-plugin`. Se for `no EC2 IMDS role found`, aplique o ajuste do IMDS (seção 4). |
| `ImagePullBackOff` | A imagem não está no ECR ou a tag é outra. Rode `aws ecr list-images --repository-name ms-catalogo`. |
| `ms-notificacoes` reinicia no começo | Normal por até 1 minuto: o MongoDB ainda está subindo. |
| Pedido fica `CRIADO` e não vira `CONFIRMADO` | Veja `kubectl logs deploy/ms-notificacoes` e a fila `pedidos.criados.dlq` no RabbitMQ. |
| Ingress sem `ADDRESS` | O load balancer ainda está sendo criado. Espere alguns minutos. |
| `curl` não resolve o nome do ELB (`Could not resolve host`) | O load balancer novo leva alguns minutos para o DNS propagar, e o computador guarda em cache a resposta "não existe". Confira o balanceador (`aws elbv2 describe-load-balancers`, estado `active`) e teste pelo IP: `nslookup <hostname-do-elb> 8.8.8.8` mostra os IPs, e `curl http://<ip>/produtos` deve responder 200 (o Ingress não filtra por nome). Para limpar o cache, rode `ipconfig /flushdns` num PowerShell **como administrador**, ou espere. |
| `kubectl ... -o jsonpath` dá erro de parse | Use o Git Bash em vez do PowerShell. |

## Caminho A: conta AWS própria (não testado)

Com permissões completas, dá para criar o cluster com `eksctl create cluster -f infra/eks/cluster.yaml` e depois seguir pelo `build-push` e `deploy`. O arquivo `infra/eks/cluster.yaml` tem a configuração, mas **não foi executado**. Confira a versão do Kubernetes suportada antes de rodar, e lembre que o ingress-nginx `controller-v1.12.1` só foi validado com o Kubernetes 1.34 no Learner Lab.
