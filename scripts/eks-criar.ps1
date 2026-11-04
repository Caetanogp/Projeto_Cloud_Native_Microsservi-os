# Cria o ambiente completo no Amazon EKS (AWS Academy Learner Lab): cluster, nos, driver de volumes,
# NGINX Ingress e a aplicacao. Leva de 25 a 30 minutos, quase tudo e espera.
#
# Pre-requisitos: laboratorio iniciado (Start Lab), credenciais coladas em %USERPROFILE%\.aws\credentials
# e as 3 imagens ja publicadas no ECR (.\scripts\build-push.ps1 -Registry <conta>.dkr.ecr.us-east-1.amazonaws.com).
#
# Uso: .\scripts\eks-criar.ps1
param(
    [string]$Cluster = "loja-cloud-native",
    [string]$Regiao = "us-east-1",
    [string]$Versao = "1.34",
    [string]$GrupoDeNos = "ng-loja",
    [string]$IngressNginx = "controller-v1.12.1"
)
# "Continue": o PowerShell 5.1 trata texto em stderr de comandos nativos como erro fatal com "Stop".
# As falhas reais sao detectadas pelo $LASTEXITCODE conferido apos cada comando.
$ErrorActionPreference = "Continue"
$inicio = Get-Date
$awsDir = "C:\Program Files\Amazon\AWSCLIV2"
if ((Test-Path $awsDir) -and ($env:Path -notlike "*$awsDir*")) { $env:Path += ";$awsDir" }

function Passo($texto) { Write-Host "`n==> $texto" -ForegroundColor Cyan }
function Falhar($texto) { Write-Host "ERRO: $texto" -ForegroundColor Red; exit 1 }
function Conferir($texto) { if ($LASTEXITCODE -ne 0) { Falhar $texto } }

# ---------------------------------------------------------------- 0) conferencias
Passo "Conferindo credenciais e pre-requisitos"
$conta = aws sts get-caller-identity --query Account --output text
Conferir "credenciais invalidas ou expiradas. Copie o bloco novo de AWS Details > AWS CLI > Show para $env:USERPROFILE\.aws\credentials (arquivo SEM extensao .txt)."
$roleArn = "arn:aws:iam::${conta}:role/LabRole"
$registry = "$conta.dkr.ecr.$Regiao.amazonaws.com"
Write-Host "conta $conta | regiao $Regiao | role $roleArn"

cmd /c "aws eks describe-cluster --name $Cluster --region $Regiao >nul 2>&1"
if ($LASTEXITCODE -eq 0) { Falhar "o cluster $Cluster ja existe. Use .\scripts\eks-apagar.ps1 antes, ou pule para o deploy." }

foreach ($s in "ms-catalogo", "ms-pedidos", "ms-notificacoes") {
    $tags = aws ecr list-images --repository-name $s --region $Regiao --filter tagStatus=TAGGED --query "imageIds[].imageTag" --output text 2>$null
    if ("$tags" -notmatch "latest") { Falhar "a imagem $s`:latest nao esta no ECR. Rode .\scripts\build-push.ps1 -Registry $registry" }
}
Write-Host "imagens no ECR: ok"

$subnets = @((aws ec2 describe-subnets --region $Regiao --filters "Name=default-for-az,Values=true" "Name=availability-zone,Values=${Regiao}a,${Regiao}b,${Regiao}c,${Regiao}d,${Regiao}f" --query "Subnets[].SubnetId" --output text) -split "\s+" | Where-Object { $_ })
if ($subnets.Count -lt 2) { Falhar "menos de 2 sub-redes encontradas na VPC padrao." }
Write-Host "sub-redes: $($subnets -join ', ')"

# ---------------------------------------------------------------- 1) cluster
Passo "Criando o cluster $Cluster (Kubernetes $Versao). Leva de 10 a 15 minutos."
aws eks create-cluster --name $Cluster --region $Regiao --kubernetes-version $Versao --role-arn $roleArn `
    --resources-vpc-config "subnetIds=$($subnets -join ','),endpointPublicAccess=true,endpointPrivateAccess=true" `
    --access-config "authenticationMode=API,bootstrapClusterCreatorAdminPermissions=true" `
    --upgrade-policy supportType=STANDARD --query "cluster.status" --output text
Conferir "falha ao criar o cluster."
aws eks wait cluster-active --name $Cluster --region $Regiao
Conferir "o cluster nao ficou ativo a tempo. Veja o console do EKS."

# ---------------------------------------------------------------- 2) grupo de nos
Passo "Criando o grupo de nos $GrupoDeNos (2 x t3.medium). Leva de 3 a 5 minutos."
aws eks create-nodegroup --cluster-name $Cluster --nodegroup-name $GrupoDeNos --region $Regiao `
    --subnets $subnets --node-role $roleArn --instance-types t3.medium `
    --scaling-config minSize=2,maxSize=3,desiredSize=2 --disk-size 20 `
    --ami-type AL2023_x86_64_STANDARD --capacity-type ON_DEMAND --query "nodegroup.status" --output text
Conferir "falha ao criar o grupo de nos."
aws eks wait nodegroup-active --cluster-name $Cluster --nodegroup-name $GrupoDeNos --region $Regiao
Conferir "o grupo de nos nao ficou ativo a tempo."

# ---------------------------------------------------------------- 3) complementos
Passo "Instalando os complementos: driver de volumes EBS CSI e metrics-server"
foreach ($addon in "aws-ebs-csi-driver", "metrics-server") {
    aws eks create-addon --cluster-name $Cluster --region $Regiao --addon-name $addon --resolve-conflicts OVERWRITE --query "addon.status" --output text
    Conferir "falha ao criar o complemento $addon."
}

# ---------------------------------------------------------------- 4) IMDS
Passo "Ajustando o limite de saltos do IMDS para 2 nas instancias do grupo de nos"
Write-Host "Motivo: sem isso o driver EBS CSI nao alcanca as credenciais da maquina e os bancos ficam Pending." -ForegroundColor Yellow
Write-Host "Contrapartida de seguranca: Pods do cluster passam a poder ler as credenciais da instancia (aceitavel no laboratorio)." -ForegroundColor Yellow
$ids = @((aws ec2 describe-instances --region $Regiao --filters "Name=tag:eks:nodegroup-name,Values=$GrupoDeNos" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text) -split "\s+" | Where-Object { $_ })
if ($ids.Count -eq 0) { Falhar "nenhuma instancia do grupo de nos encontrada." }
foreach ($id in $ids) {
    aws ec2 modify-instance-metadata-options --region $Regiao --instance-id $id --http-put-response-hop-limit 2 --http-endpoint enabled --query "InstanceMetadataOptions.HttpPutResponseHopLimit" --output text
    Conferir "falha ao ajustar o IMDS da instancia $id."
}

# ---------------------------------------------------------------- 5) kubectl + driver de volumes
Passo "Conectando o kubectl e aguardando o driver de volumes"
aws eks update-kubeconfig --name $Cluster --region $Regiao | Out-Null
Conferir "falha no update-kubeconfig."
kubectl wait --for=condition=available deployment/ebs-csi-controller -n kube-system --timeout=420s
if ($LASTEXITCODE -ne 0) { Write-Host "AVISO: o ebs-csi-controller ainda nao esta disponivel. Veja: kubectl get pods -n kube-system" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 6) NGINX Ingress
Passo "Instalando o NGINX Ingress Controller ($IngressNginx)"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$IngressNginx/deploy/static/provider/aws/deploy.yaml"
Conferir "falha ao instalar o NGINX Ingress."
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=240s
Conferir "o NGINX Ingress nao ficou pronto."

# ---------------------------------------------------------------- 7) aplicacao
Passo "Implantando a aplicacao (bancos, RabbitMQ, 3 microsservicos e Ingress)"
& (Join-Path $PSScriptRoot "deploy.ps1") -Registry $registry

$min = [math]::Round(((Get-Date) - $inicio).TotalMinutes)
Write-Host "`nPronto em $min minutos." -ForegroundColor Green
Write-Host "Teste com: .\scripts\demo.ps1 -BaseUrl http://<hostname-do-elb-acima>" -ForegroundColor Green
Write-Host "Ao terminar, apague tudo com: .\scripts\eks-apagar.ps1" -ForegroundColor Green
