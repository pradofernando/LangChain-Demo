# ============================================================================
# start-langchain.ps1
# ============================================================================
# Starts the LangChain agent (Python/FastAPI) on port 8000.
# Run this in a separate terminal window.
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "🐍 Starting LangChain Agent..." -ForegroundColor Cyan
Write-Host ""

# Get repository root
$RepoRoot = Split-Path -Parent $PSScriptRoot

# Navigate to LangChain agent directory
Push-Location "$RepoRoot\src\LangChainAgent"

# Always (re)install — fast no-op if already satisfied
Write-Host "📦 Ensuring Python dependencies are installed..." -ForegroundColor Yellow
pip install -q -r requirements.txt

# Load .env into the current process so AZURE_OPENAI_* vars are visible to python
$envFile = Join-Path $RepoRoot ".env"
if (Test-Path $envFile) {
    Write-Host "🔐 Loading environment variables from .env" -ForegroundColor Yellow
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=\s]+)\s*=\s*(.*)$') {
            $name  = $matches[1]
            $value = $matches[2].Trim('"').Trim("'")
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

# Start the agent
Write-Host "🚀 Starting FastAPI server on http://localhost:8000" -ForegroundColor Green
Write-Host "   Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

python main.py

Pop-Location
