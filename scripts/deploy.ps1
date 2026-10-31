# Uso: .\scripts\deploy.ps1 -Registry <registry> [-Tag latest]
# Renderiza o kustomize, troca as imagens locais pelas do registry e aplica no cluster atual.
param(
    [Parameter(Mandatory = $true)][string]$Registry,
    [string]$Tag = "latest"
)
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot

Write-Host "==> Aplicando manifestos no cluster: $(kubectl config current-context)"
$yaml = kubectl kustomize (Join-Path $raiz "k8s")
if ($LASTEXITCODE -ne 0) { throw "Falha ao renderizar o kustomize" }
$yaml = $yaml -replace 'image: (ms-catalogo|ms-pedidos|ms-notificacoes):latest', "image: $Registry/`$1:$Tag"
$yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw "Falha no kubectl apply" }

Write-Host "==> Aguardando os bancos e o RabbitMQ"
kubectl -n loja rollout status statefulset/mysql-catalogo --timeout=300s
kubectl -n loja rollout status statefulset/postgres-pedidos --timeout=300s
kubectl -n loja rollout status statefulset/mongo-notificacoes --timeout=300s
kubectl -n loja rollout status deployment/rabbitmq --timeout=300s

Write-Host "==> Aguardando os microsserviços"
foreach ($d in "ms-catalogo", "ms-pedidos", "ms-notificacoes") {
    kubectl -n loja rollout status "deployment/$d" --timeout=300s
}

kubectl -n loja get pods, svc, ingress -o wide
Write-Host ""
Write-Host "Hostname do Ingress (pode levar alguns minutos para resolver no DNS):"
kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
Write-Host ""
