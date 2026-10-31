# Uso: .\scripts\build-push.ps1 -Registry <registry> [-Tag latest]
#   ECR:        .\scripts\build-push.ps1 -Registry 123456789012.dkr.ecr.us-east-1.amazonaws.com
#   Docker Hub: .\scripts\build-push.ps1 -Registry meuusuario
param(
    [Parameter(Mandatory = $true)][string]$Registry,
    [string]$Tag = "latest"
)
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$servicos = "ms-catalogo", "ms-pedidos", "ms-notificacoes"

if ($Registry -match '\.dkr\.ecr\.([^.]+)\.amazonaws\.com$') {
    $regiao = $Matches[1]
    Write-Host "==> Login no ECR ($regiao)"
    aws ecr get-login-password --region $regiao | docker login --username AWS --password-stdin $Registry
    foreach ($s in $servicos) {
        aws ecr describe-repositories --repository-names $s --region $regiao *> $null
        if ($LASTEXITCODE -ne 0) {
            aws ecr create-repository --repository-name $s --region $regiao | Out-Null
        }
    }
}

foreach ($s in $servicos) {
    Write-Host "==> Build e push de $s"
    docker build -t "$Registry/${s}:$Tag" (Join-Path $raiz $s)
    if ($LASTEXITCODE -ne 0) { throw "Falha no build de $s" }
    docker push "$Registry/${s}:$Tag"
    if ($LASTEXITCODE -ne 0) { throw "Falha no push de $s" }
}
Write-Host "Imagens publicadas em $Registry (tag $Tag)"
