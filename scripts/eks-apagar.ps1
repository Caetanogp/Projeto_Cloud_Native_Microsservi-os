# Apaga o ambiente do EKS na ordem certa, para nao sobrar nada cobrando:
# aplicacao e volumes -> NGINX Ingress e load balancer -> grupo de nos -> cluster.
# As imagens do ECR sao MANTIDAS (custam centavos). Use -ApagarECR para remove-las tambem.
#
# Uso: .\scripts\eks-apagar.ps1 [-ApagarECR]
param(
    [string]$Cluster = "loja-cloud-native",
    [string]$Regiao = "us-east-1",
    [string]$GrupoDeNos = "ng-loja",
    [string]$IngressNginx = "controller-v1.12.1",
    [switch]$ApagarECR
)
$ErrorActionPreference = "Continue"
$awsDir = "C:\Program Files\Amazon\AWSCLIV2"
if ((Test-Path $awsDir) -and ($env:Path -notlike "*$awsDir*")) { $env:Path += ";$awsDir" }

function Passo($texto) { Write-Host "`n==> $texto" -ForegroundColor Cyan }
function Falhar($texto) { Write-Host "ERRO: $texto" -ForegroundColor Red; exit 1 }

Passo "Conferindo credenciais"
$conta = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) { Falhar "credenciais invalidas ou expiradas. Cole o bloco novo de AWS Details > AWS CLI > Show em $env:USERPROFILE\.aws\credentials" }

cmd /c "aws eks describe-cluster --name $Cluster --region $Regiao >nul 2>&1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "O cluster $Cluster nao existe. Pulando para a verificacao final."
} else {
    aws eks update-kubeconfig --name $Cluster --region $Regiao | Out-Null

    Passo "1/4 Apagando a aplicacao (namespace loja) e os volumes dos bancos"
    kubectl delete namespace loja --ignore-not-found --timeout=300s
    for ($i = 1; $i -le 18; $i++) {
        $vol = aws ec2 describe-volumes --region $Regiao --filters "Name=tag-key,Values=kubernetes.io/created-for/pvc/namespace" --query "length(Volumes)" --output text
        Write-Host "  volumes de PVC restantes: $vol"
        if ($vol -eq "0") { break }
        Start-Sleep -Seconds 10
    }

    Passo "2/4 Apagando o NGINX Ingress e o load balancer"
    kubectl delete -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$IngressNginx/deploy/static/provider/aws/deploy.yaml" --ignore-not-found --timeout=240s
    for ($i = 1; $i -le 18; $i++) {
        $lb = aws elbv2 describe-load-balancers --region $Regiao --query "length(LoadBalancers)" --output text
        Write-Host "  load balancers na conta: $lb"
        if ($lb -eq "0") { break }
        Start-Sleep -Seconds 10
    }

    Passo "3/4 Apagando o grupo de nos $GrupoDeNos (leva alguns minutos)"
    aws eks delete-nodegroup --cluster-name $Cluster --nodegroup-name $GrupoDeNos --region $Regiao --query "nodegroup.status" --output text
    aws eks wait nodegroup-deleted --cluster-name $Cluster --nodegroup-name $GrupoDeNos --region $Regiao

    Passo "4/4 Apagando o cluster $Cluster"
    aws eks delete-cluster --name $Cluster --region $Regiao --query "cluster.status" --output text
    aws eks wait cluster-deleted --name $Cluster --region $Regiao
}

if ($ApagarECR) {
    Passo "Apagando os repositorios do ECR"
    foreach ($r in "ms-catalogo", "ms-pedidos", "ms-notificacoes") {
        cmd /c "aws ecr delete-repository --repository-name $r --region $Regiao --force >nul 2>&1"
        Write-Host "  $r : removido (codigo $LASTEXITCODE)"
    }
}

Passo "Verificacao final: tudo abaixo deve ser 0"
Write-Host ("clusters EKS:           " + (aws eks list-clusters --region $Regiao --query "length(clusters)" --output text))
Write-Host ("instancias EC2:         " + (aws ec2 describe-instances --region $Regiao --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "length(Reservations[].Instances[])" --output text))
Write-Host ("load balancers:         " + (aws elbv2 describe-load-balancers --region $Regiao --query "length(LoadBalancers)" --output text))
Write-Host ("volumes EBS:            " + (aws ec2 describe-volumes --region $Regiao --query "length(Volumes)" --output text))
Write-Host ("NAT gateways ativos:    " + (aws ec2 describe-nat-gateways --region $Regiao --filter "Name=state,Values=available,pending" --query "length(NatGateways)" --output text))
Write-Host ("IPs elasticos:          " + (aws ec2 describe-addresses --region $Regiao --query "length(Addresses)" --output text))
if (-not $ApagarECR) { Write-Host "(os repositorios do ECR foram mantidos de proposito; use -ApagarECR depois da apresentacao)" -ForegroundColor Yellow }
