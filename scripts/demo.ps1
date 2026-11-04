# Demonstração do fluxo completo pelo Ingress (ou pelo gateway local do Docker Compose).
# Uso: .\scripts\demo.ps1 -BaseUrl http://<hostname-do-elb>      (local: http://localhost:8080)
param([string]$BaseUrl = "http://localhost:8080")
$ErrorActionPreference = "Stop"
$base = $BaseUrl.TrimEnd("/")

function Titulo($texto) { Write-Host "`n=== $texto ===" -ForegroundColor Cyan }
function Get-Json($url) { Invoke-RestMethod -Uri $url -Method Get }

Titulo "1) Ingress: GET $base/produtos"
(Get-Json "$base/produtos") | ConvertTo-Json -Depth 5

Titulo "2) Balanceamento: 12 chamadas a GET /produtos (campo 'pod' da resposta)"
1..12 | ForEach-Object { (Get-Json "$base/produtos").pod } | Group-Object | Sort-Object Name |
    ForEach-Object { "{0,3} x {1}" -f $_.Count, $_.Name }

Titulo "3) Fluxo integrado: POST /pedidos (REST ao catálogo + publicação no RabbitMQ)"
$corpo = @{ cliente = "Caetano"; produto_id = 1; quantidade = 2 } | ConvertTo-Json
$criado = Invoke-RestMethod -Uri "$base/pedidos" -Method Post -ContentType "application/json" -Body $corpo
$criado | ConvertTo-Json -Depth 5
$id = $criado.pedido.id
Write-Host "-> catalogo_pod = $($criado.catalogo_pod): réplica do catálogo que atendeu a chamada REST do ms-pedidos"

Titulo "4) Aguardando o ms-notificacoes consumir a mensagem..."
$status = ""
for ($i = 0; $i -lt 15; $i++) {
    $status = (Get-Json "$base/pedidos/$id").pedido.status
    if ($status -eq "CONFIRMADO") { break }
    Start-Sleep -Seconds 1
}
(Get-Json "$base/pedidos/$id") | ConvertTo-Json -Depth 5
Write-Host "-> status final: $status"

Titulo "5) Notificação gravada no MongoDB pelo ms-notificacoes"
(Get-Json "$base/notificacoes/pedido/$id") | ConvertTo-Json -Depth 5

Titulo "6) Estoque do produto 1 depois da reserva"
(Get-Json "$base/produtos/1") | ConvertTo-Json -Depth 5

if ($status -eq "CONFIRMADO") {
    Write-Host "`nFluxo OK: REST + RabbitMQ funcionando." -ForegroundColor Green
} else {
    Write-Host "`nPedido não foi confirmado. Veja os logs dos serviços." -ForegroundColor Red
    exit 1
}
