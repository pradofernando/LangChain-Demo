# ============================================================================
# run-local.ps1
# ============================================================================
# Starts both the LangChain agent (Python) and .NET host (ASP.NET Core) 
# for local development and demo purposes.
#
# Prerequisites:
#   - Python 3.11+ with pip
#   - .NET 8.0 SDK
#   - PowerShell 7+ (recommended)
#
# Usage:
#   .\scripts\run-local.ps1
#
# Press Ctrl+C to stop both services.
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting LangChain → Foundry Demo (Local Mode)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Get repository root
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot

# ============================================================================
# CHECK PREREQUISITES
# ============================================================================

Write-Host "📋 Checking prerequisites..." -ForegroundColor Yellow

# Check Python
try {
    $pythonVersion = python --version 2>&1
    Write-Host "  ✅ Python: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Python not found. Please install Python 3.11+." -ForegroundColor Red
    exit 1
}

# Check .NET
try {
    $dotnetVersion = dotnet --version 2>&1
    Write-Host "  ✅ .NET SDK: $dotnetVersion" -ForegroundColor Green
} catch {
    Write-Host "  ❌ .NET SDK not found. Please install .NET 8.0+." -ForegroundColor Red
    exit 1
}

Write-Host ""

# ============================================================================
# INSTALL DEPENDENCIES
# ============================================================================

Write-Host "📦 Installing dependencies..." -ForegroundColor Yellow

# Python dependencies
Write-Host "  Installing Python packages..." -ForegroundColor Gray
Push-Location "$RepoRoot\src\LangChainAgent"
pip install -r requirements.txt 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ Failed to install Python packages. Run manually to see errors:" -ForegroundColor Red
    Write-Host "     cd src/LangChainAgent" -ForegroundColor Yellow
    Write-Host "     pip install -r requirements.txt" -ForegroundColor Yellow
    Pop-Location
    Pop-Location
    exit 1
}
Write-Host "  ✅ Python packages installed" -ForegroundColor Green
Pop-Location

# .NET dependencies
Write-Host "  Restoring .NET packages..." -ForegroundColor Gray
Push-Location "$RepoRoot\src\DemoHost"
try {
    dotnet restore --verbosity quiet
    Write-Host "  ✅ .NET packages restored" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Failed to restore .NET packages" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location

Write-Host ""

# ============================================================================
# START SERVICES
# ============================================================================

Write-Host "🔧 Starting services..." -ForegroundColor Yellow
Write-Host ""

# Start LangChain agent in background
Write-Host "  Starting LangChain agent (Python/FastAPI) on port 8000..." -ForegroundColor Cyan
$pythonProcess = Start-Process -FilePath "$PSScriptRoot\start-python.cmd" -PassThru -WindowStyle Hidden

# Wait for LangChain agent to be ready
Write-Host "  Waiting for LangChain agent to start..." -ForegroundColor Gray
$maxRetries = 90  # 45 seconds total
$retry = 0
$langchainReady = $false

while ($retry -lt $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8000/health" -Method GET -TimeoutSec 1 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $langchainReady = $true
            break
        }
    } catch {
        # Service not ready yet
    }
    Start-Sleep -Milliseconds 500
    $retry++
}

if (-not $langchainReady) {
    Write-Host "  ❌ LangChain agent failed to start (timeout after 45 seconds)" -ForegroundColor Red
    Write-Host "     Try running manually: cd src/LangChainAgent; python main.py" -ForegroundColor Yellow
    Stop-Process -Id $pythonProcess.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "  ✅ LangChain agent ready at http://localhost:8000" -ForegroundColor Green
Write-Host ""

# Start .NET host in background
Write-Host "  Starting .NET host (ASP.NET Core) on port 8080..." -ForegroundColor Cyan
$dotnetProcess = Start-Process -FilePath "$PSScriptRoot\start-dotnet.cmd" -PassThru -WindowStyle Hidden

# Wait for .NET host to be ready
Write-Host "  Waiting for .NET host to start..." -ForegroundColor Gray
$retry = 0
$dotnetReady = $false

while ($retry -lt $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -Method GET -TimeoutSec 1 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $dotnetReady = $true
            break
        }
    } catch {
        # Service not ready yet
    }
    Start-Sleep -Milliseconds 500
    $retry++
}

if (-not $dotnetReady) {
    Write-Host "  ❌ .NET host failed to start (timeout after 45 seconds)" -ForegroundColor Red
    Stop-Process -Id $pythonProcess.Id, $dotnetProcess.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "  ✅ .NET host ready at http://localhost:8080" -ForegroundColor Green
Write-Host ""

# ============================================================================
# READY
# ============================================================================

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ Demo is running!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "🔗 Endpoints:" -ForegroundColor Cyan
Write-Host "  LangChain Agent:  http://localhost:8000" -ForegroundColor White
Write-Host "  .NET Host:        http://localhost:8080" -ForegroundColor White
Write-Host "  API Docs:         http://localhost:8000/docs" -ForegroundColor White
Write-Host ""
Write-Host "💡 Try it:" -ForegroundColor Cyan
Write-Host "  .\scripts\test-demo.ps1" -ForegroundColor White
Write-Host ""
Write-Host "📚 For presentation script, see: DEMO.md" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to stop all services..." -ForegroundColor Yellow

# ============================================================================
# KEEP RUNNING & HANDLE SHUTDOWN
# ============================================================================

try {
    # Keep script running and monitor processes
    while ($true) {
        # Check if processes are still running (check for python.exe since we start via CMD)
        $pythonRunning = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "" }
        $dotnetRunning = Get-Process dotnet -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "" }
        
        if (-not $pythonRunning -or -not $dotnetRunning) {
            Write-Host ""
            Write-Host "⚠️  One or more services stopped unexpectedly" -ForegroundColor Yellow
            
            if (-not $pythonRunning) {
                Write-Host "LangChain agent (Python) is not running" -ForegroundColor Red
            }
            
            if (-not $dotnetRunning) {
                Write-Host ".NET host is not running" -ForegroundColor Red
            }
            
            break
        }
        
        Start-Sleep -Seconds 2
    }
} finally {
    # Cleanup on exit (Ctrl+C or error)
    Write-Host ""
    Write-Host "🛑 Stopping services..." -ForegroundColor Yellow
    
    # Kill all python and dotnet processes related to our demo
    Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process dotnet -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*DemoHost*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $pythonProcess.Id, $dotnetProcess.Id -Force -ErrorAction SilentlyContinue
    
    Write-Host "✅ All services stopped" -ForegroundColor Green
    Pop-Location
}
