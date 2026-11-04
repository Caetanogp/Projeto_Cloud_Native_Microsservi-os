# Uso: .\scripts\build-push.ps1 -Registry <registry> [-Tag latest]
#   ECR:        .\scripts\build-push.ps1 -Registry 123456789012.dkr.ecr.us-east-1.amazonaws.com
#   Docker Hub: .\scripts\build-push.ps1 -Registry meuusuario
param(
    [Parameter(Mandatory = $true)][string]$Registry,
    [string]$Tag = "latest"
)
# "Continue": o docker escreve o progresso do build em stderr e o PowerShell 5.1 trataria isso como erro fatal.
# As falhas reais são detectadas pelo $LASTEXITCODE conferido após cada comando.
$ErrorActionPreference = "Continue"
$raiz = Split-Path -Parent $PSScriptRoot
$servicos = "ms-catalogo", "ms-pedidos", "ms-notificacoes"

if ($Registry -match '\.dkr\.ecr\.([^.]+)\.amazonaws\.com$') {
    $regiao = $Matches[1]
    Write-Host "==> Login no ECR ($regiao)"
    # O pipe do PowerShell 5.1 corrompe a senha (docker login responde 400 Bad Request); o cmd.exe não.
    cmd /c "aws ecr get-login-password --region $regiao | docker login --username AWS --password-stdin $Registry"
    if ($LASTEXITCODE -ne 0) { throw "Falha no login do ECR" }
    foreach ($s in $servicos) {
        # cmd.exe silencia o erro "repositório não encontrado" sem disparar o ErrorActionPreference=Stop
        cmd /c "aws ecr describe-repositories --repository-names $s --region $regiao >nul 2>&1"
        if ($LASTEXITCODE -ne 0) {
            cmd /c "aws ecr create-repository --repository-name $s --region $regiao >nul"
            if ($LASTEXITCODE -ne 0) { throw "Falha ao criar o repositório $s no ECR" }
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
