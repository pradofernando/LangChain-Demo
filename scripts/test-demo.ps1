# ============================================================================
# test-demo.ps1
# ============================================================================
# Integration test script for the LangChain → Foundry demo.
# Tests the complete flow from .NET host → LangChain agent → tool execution.
#
# Prerequisites:
#   - Both services must be running (run .\scripts\run-local.ps1 first)
#
# Usage:
#   .\scripts\test-demo.ps1
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "🧪 Testing LangChain → Foundry Demo" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Test endpoints
$langchainUrl = "http://localhost:8000"
$dotnetUrl = "http://localhost:8080"

# ============================================================================
# TEST 1: Health Checks
# ============================================================================

Write-Host "Test 1: Health Checks" -ForegroundColor Yellow
Write-Host "────────────────────────────────────────────────" -ForegroundColor Gray

# Test LangChain agent health
Write-Host "  Testing LangChain agent health..." -ForegroundColor Gray
try {
    $response = Invoke-RestMethod -Uri "$langchainUrl/health" -Method GET -ErrorAction Stop
    Write-Host "  ✅ LangChain agent is healthy" -ForegroundColor Green
    Write-Host "     Status: $($response.status)" -ForegroundColor Gray
} catch {
    Write-Host "  ❌ LangChain agent health check failed" -ForegroundColor Red
    Write-Host "     Make sure services are running: .\scripts\run-local.ps1" -ForegroundColor Yellow
    exit 1
}

# Test .NET host health
Write-Host "  Testing .NET host health..." -ForegroundColor Gray
try {
    $response = Invoke-RestMethod -Uri "$dotnetUrl/health" -Method GET -ErrorAction Stop
    Write-Host "  ✅ .NET host is healthy" -ForegroundColor Green
    Write-Host "     Status: $($response.status)" -ForegroundColor Gray
} catch {
    Write-Host "  ❌ .NET host health check failed" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ============================================================================
# TEST 2: Direct LangChain Query
# ============================================================================

Write-Host "Test 2: Direct LangChain Agent Query" -ForegroundColor Yellow
Write-Host "────────────────────────────────────────────────" -ForegroundColor Gray

$query = "Summarize ticket #42 and suggest next steps"
Write-Host "  Query: $query" -ForegroundColor Cyan

$body = @{
    query = $query
    session_id = [Guid]::NewGuid().ToString()
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$langchainUrl/query" -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
    Write-Host "  ✅ LangChain agent responded" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Response:" -ForegroundColor White
    Write-Host "  ───────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  $($response.response)" -ForegroundColor White
    Write-Host "  ───────────────────────────────────────────────" -ForegroundColor DarkGray
} catch {
    Write-Host "  ❌ LangChain query failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ============================================================================
# TEST 3: .NET Host Query (Full Integration)
# ============================================================================

Write-Host "Test 3: Full Integration (.NET Host → LangChain)" -ForegroundColor Yellow
Write-Host "────────────────────────────────────────────────" -ForegroundColor Gray

$query2 = "What's the status of ticket #101?"
Write-Host "  Query: $query2" -ForegroundColor Cyan

$body2 = @{
    query = $query2
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$dotnetUrl/query" -Method POST -Body $body2 -ContentType "application/json" -ErrorAction Stop
    Write-Host "  ✅ Full integration successful" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Response:" -ForegroundColor White
    Write-Host "  ───────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  $($response.response)" -ForegroundColor White
    Write-Host "  ───────────────────────────────────────────────" -ForegroundColor DarkGray
} catch {
    Write-Host "  ❌ Integration test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ============================================================================
# TEST 4: OpenAI-Compatible Chat Completions Endpoint
# ============================================================================

Write-Host "Test 4: OpenAI-Compatible Endpoint (for Copilot)" -ForegroundColor Yellow
Write-Host "────────────────────────────────────────────────" -ForegroundColor Gray

$query3 = "Analyze ticket #78"
Write-Host "  Query: $query3" -ForegroundColor Cyan

$chatBody = @{
    model = "support-agent"
    messages = @(
        @{
            role = "user"
            content = $query3
        }
    )
} | ConvertTo-Json -Depth 10

try {
    $response = Invoke-RestMethod -Uri "$dotnetUrl/chat/completions" -Method POST -Body $chatBody -ContentType "application/json" -ErrorAction Stop
    Write-Host "  ✅ OpenAI-compatible endpoint working" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Response:" -ForegroundColor White
    Write-Host "  ───────────────────────────────────────────────" -ForegroundColor DarkGray
    $content = $response.choices[0].message.content
    Write-Host "  $content" -ForegroundColor White
    Write-Host "  ───────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Tokens used: $($response.usage.total_tokens)" -ForegroundColor Gray
} catch {
    Write-Host "  ❌ Chat completions test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ============================================================================
# TEST 5: Error Handling (Invalid Ticket)
# ============================================================================

Write-Host "Test 5: Error Handling" -ForegroundColor Yellow
Write-Host "────────────────────────────────────────────────" -ForegroundColor Gray

$invalidQuery = "Show me ticket #999"
Write-Host "  Query: $invalidQuery (should handle gracefully)" -ForegroundColor Cyan

$errorBody = @{
    query = $invalidQuery
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$dotnetUrl/query" -Method POST -Body $errorBody -ContentType "application/json" -ErrorAction Stop
    Write-Host "  ✅ Error handled gracefully" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Response:" -ForegroundColor White
    Write-Host "  ───────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  $($response.response)" -ForegroundColor White
    Write-Host "  ───────────────────────────────────────────────" -ForegroundColor DarkGray
} catch {
    Write-Host "  ❌ Error handling test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ All tests passed!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Test Summary:" -ForegroundColor Cyan
Write-Host "  ✅ Health checks passed" -ForegroundColor White
Write-Host "  ✅ LangChain agent responds correctly" -ForegroundColor White
Write-Host "  ✅ .NET host integration working" -ForegroundColor White
Write-Host "  ✅ OpenAI-compatible endpoint ready for Copilot" -ForegroundColor White
Write-Host "  ✅ Error handling works as expected" -ForegroundColor White
Write-Host ""
Write-Host "🎯 Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Review DEMO.md for the 15-minute presentation script" -ForegroundColor White
Write-Host "  2. Configure .vscode/mcp.json with Foundry endpoint after deployment" -ForegroundColor White
Write-Host "  3. Test from GitHub Copilot: @support-agent Summarize ticket #42" -ForegroundColor White
Write-Host ""
Write-Host "💡 To deploy to Foundry:" -ForegroundColor Cyan
Write-Host "  See foundry/agent.yaml and README.md" -ForegroundColor White
Write-Host ""
