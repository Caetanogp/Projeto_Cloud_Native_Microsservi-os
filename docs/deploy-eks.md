# Deploy no Amazon EKS

Este guia leva do zero ao sistema rodando no EKS. O ambiente de onde escrevi o código não tinha AWS CLI, eksctl nem credenciais, então **nada abaixo foi executado contra a AWS**. Os manifestos foram validados com `kubectl kustomize`.

## 0. Pré-requisitos

- AWS CLI v2, `kubectl`, Docker e (conta própria) `eksctl` instalados.
- Credenciais configuradas: `aws configure`, ou, no Learner Lab, copie as credenciais do painel "AWS Details" para `~/.aws/credentials`.
- Confira com `aws sts get-caller-identity`.

## 1. Criar o cluster

### Caminho A: conta AWS própria

```bash
eksctl create cluster -f infra/eks/cluster.yaml
```

Leva cerca de 15 a 20 minutos e já instala o addon `aws-ebs-csi-driver`, usado pelos bancos. A versão do Kubernetes está em `infra/eks/cluster.yaml`; confira as versões suportadas com `aws eks describe-cluster-versions` antes de rodar.

### Caminho B: AWS Academy Learner Lab

O Learner Lab não permite criar IAM roles, então o `eksctl` não funciona. Use a `LabRole` que já existe.

1. Console AWS → EKS → **Create cluster** (modo personalizado).
2. Nome `loja-cloud-native`, **Cluster IAM role = `LabRole`**.
3. Rede: VPC padrão e pelo menos 2 subnets em zonas diferentes.
4. Addons: `CoreDNS`, `kube-proxy`, `Amazon VPC CNI` e **`Amazon EBS CSI Driver`**. No addon do EBS CSI, deixe o papel de serviço em branco ou use a `LabRole`, se o console pedir.
5. Quando o cluster ficar **Ativo**, abra a aba *Compute* → **Add node group**: **Node IAM role = `LabRole`**, `t3.medium`, mínimo 2 e máximo 3 nós.
6. Conecte o kubectl:
   ```bash
   aws eks update-kubeconfig --name loja-cloud-native --region us-east-1
   kubectl get nodes
   ```

Observações do Learner Lab:
- As credenciais expiram quando a sessão do laboratório acaba. Renove o `~/.aws/credentials` e rode o `update-kubeconfig` de novo.
- Se o PVC dos bancos ficar `Pending` (veja a seção de problemas abaixo), o driver EBS não tem permissão no ambiente. Peça ajuda ao professor ou veja a alternativa lá.

## 2. Instalar o NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/aws/deploy.yaml
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

O manifesto `provider/aws` cria um Service `LoadBalancer`, e a AWS provisiona o ELB. O hostname aparece em `EXTERNAL-IP` depois de alguns minutos.

A versão `controller-v1.12.1` é fixa de propósito. O projeto ingress-nginx foi anunciado como em fim de vida, então confira no repositório `kubernetes/ingress-nginx` se existe uma versão mais nova compatível com a sua versão do Kubernetes.

## 3. Publicar as imagens

### Opção 1: Amazon ECR

```bash
# <conta> = aws sts get-caller-identity --query Account --output text
./scripts/build-push.sh <conta>.dkr.ecr.us-east-1.amazonaws.com
```

O script faz login no ECR, cria os repositórios que não existirem, e faz build e push das 3 imagens. No Windows: `.\scripts\build-push.ps1 -Registry <conta>.dkr.ecr.us-east-1.amazonaws.com`.

### Opção 2: Docker Hub

```bash
docker login
./scripts/build-push.sh <seu-usuario-dockerhub>
```

Os repositórios criados no Docker Hub são públicos por padrão, então os nós do EKS conseguem baixar sem credencial.

## 4. Fazer o deploy

```bash
./scripts/deploy.sh <registry>
# Windows: .\scripts\deploy.ps1 -Registry <registry>
```

O script renderiza o `k8s/` com kustomize, troca `ms-catalogo:latest` etc. por `<registry>/ms-catalogo:latest`, aplica no cluster e espera os rollouts. No final mostra os recursos e o hostname do ELB.

Para aplicar sem o script (imagens já com o nome final):

```bash
kubectl apply -k k8s
```

## 5. Testar

```bash
HOST=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
./scripts/demo.sh http://$HOST
```

O DNS do ELB pode levar alguns minutos para propagar. Se `curl` disser que não resolve o nome, espere e tente de novo.

## 6. Comandos úteis

```bash
kubectl get nodes,pods,svc,ingress -n loja -o wide
kubectl logs -n loja deploy/ms-pedidos
kubectl logs -n loja deploy/ms-notificacoes
kubectl logs -n loja deploy/ms-catalogo --all-containers --prefix
kubectl port-forward -n loja svc/rabbitmq 15672:15672     # painel em http://localhost:15672 (loja / loja123)
kubectl scale -n loja deploy/ms-catalogo --replicas=5
```

## 7. Problemas comuns

| Sintoma | Causa provável e solução |
|---|---|
| Pods dos bancos `Pending`, PVC `Pending` | O driver EBS CSI não está instalado ou sem permissão. Confira `kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver` e `kubectl describe pvc -n loja`. Alternativa só para demonstração: troque `storageClassName: gp3` por um volume `emptyDir` nos três arquivos de banco (os dados somem se o Pod reiniciar). |
| `ImagePullBackOff` | Registry errado, imagem privada sem credencial, ou o push não terminou. Confira `kubectl describe pod`. No ECR, o papel dos nós precisa de `AmazonEC2ContainerRegistryReadOnly` (a `LabRole` já tem). |
| `ms-notificacoes` reiniciando no começo | Normal por até 1 minuto: o MongoDB ainda está subindo. Se persistir, veja `kubectl logs`. |
| Pedido fica `CRIADO` e não vira `CONFIRMADO` | Veja `kubectl logs deploy/ms-notificacoes` e a fila `pedidos.criados.dlq` no painel do RabbitMQ. |
| Ingress sem `ADDRESS` | O ELB ainda está sendo criado, ou as subnets não têm as tags de load balancer. Espere alguns minutos e confira `kubectl describe svc -n ingress-nginx ingress-nginx-controller`. |
| Ingress responde 404 do NGINX | Rota fora de `/produtos`, `/pedidos`, `/notificacoes`, ou `kubectl get ingress -n loja` sem a regra. |
| Admission webhook do ingress falha no `apply` | O controller ainda não está pronto. Espere o rollout do passo 2 e aplique de novo. |

## 8. Desligar tudo (para não gerar custo)

```bash
kubectl delete -k k8s                      # remove também o ELB criado pelo Ingress se você deletar o ingress-nginx antes do cluster
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/aws/deploy.yaml
eksctl delete cluster -f infra/eks/cluster.yaml    # caminho A
```

No caminho B, apague o node group e depois o cluster pelo console. Delete os volumes EBS que sobrarem e os repositórios do ECR.
