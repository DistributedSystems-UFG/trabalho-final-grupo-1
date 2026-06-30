# Reseta o ambiente CollabDocs do zero (apaga banco, filas e imagens locais do compose).
# Uso: .\infra\reset.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Push-Location $Root
try {
    Write-Host "Parando containers e removendo volumes infra_postgres_data / infra_rabbitmq_data..." -ForegroundColor Cyan
    docker compose -f infra/docker-compose.yml down -v --remove-orphans --rmi local

    Write-Host "Removendo volumes Docker orfaos (nao usados)..." -ForegroundColor Cyan
    docker volume prune -f | Out-Null

    Write-Host ""
    Write-Host "Ambiente resetado." -ForegroundColor Green
    Write-Host "Para subir do zero:" -ForegroundColor Yellow
    Write-Host "  docker compose -f infra/docker-compose.yml up -d --build"
    Write-Host ""
    Write-Host "No navegador: limpe o localStorage ou use janela anonima (F12 > Application > Local Storage > Clear)." -ForegroundColor Yellow
}
finally {
    Pop-Location
}
