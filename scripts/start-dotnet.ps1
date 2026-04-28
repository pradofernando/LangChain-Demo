# ============================================================================
# start-dotnet.ps1
# ============================================================================
# Starts the .NET host (ASP.NET Core) on port 8080.
# Run this in a separate terminal window after starting the LangChain agent.
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "🔷 Starting .NET Host..." -ForegroundColor Cyan
Write-Host ""

# Get repository root
$RepoRoot = Split-Path -Parent $PSScriptRoot

# Navigate to .NET host directory
Push-Location "$RepoRoot\src\DemoHost"

# Restore dependencies if needed
Write-Host "📦 Restoring .NET dependencies..." -ForegroundColor Yellow
dotnet restore --verbosity quiet

# Build
Write-Host "🔨 Building..." -ForegroundColor Yellow
dotnet build --verbosity quiet

# Start the host
Write-Host "🚀 Starting ASP.NET Core on http://localhost:8080" -ForegroundColor Green
Write-Host "   Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

$env:ASPNETCORE_URLS = "http://localhost:8080"
dotnet run --no-build

Pop-Location
