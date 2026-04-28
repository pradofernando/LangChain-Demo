using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using System.Text.Json;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

// ============================================================================
// CONFIGURATION
// ============================================================================

// Load LangChain agent endpoint from configuration or user secrets
var langChainBaseUrl = builder.Configuration["LangChainAgent:BaseUrl"] 
    ?? "http://localhost:8000";

builder.Logging.AddConsole();

// ============================================================================
// HTTP CLIENT SETUP
// ============================================================================

// Register HTTP client for calling the LangChain agent
builder.Services.AddHttpClient("LangChainAgent", client =>
{
    client.BaseAddress = new Uri(langChainBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
});

// ============================================================================
// SEMANTIC KERNEL SETUP
// ============================================================================

// NOTE: In a real deployment, use Azure OpenAI and load keys from Key Vault
// For demo purposes, we're using a mock/passthrough approach
builder.Services.AddSingleton<Kernel>(sp =>
{
    var kernelBuilder = Kernel.CreateBuilder();
    
    // For this demo, we'll create a lightweight kernel without requiring OpenAI keys
    // In production, add: .AddAzureOpenAIChatCompletion(modelId, endpoint, apiKey)
    
    return kernelBuilder.Build();
});

// ============================================================================
// CORS (for local testing from browser/Copilot)
// ============================================================================

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

var app = builder.Build();

app.UseCors();
// Serve the static frontend (wwwroot/index.html)
app.UseDefaultFiles();
app.UseStaticFiles();

// ============================================================================
// HELPER: Call LangChain Agent
// ============================================================================

async Task<string> CallLangChainAgentAsync(HttpClient httpClient, string query)
{
    var requestBody = new
    {
        query = query,
        session_id = Guid.NewGuid().ToString()
    };

    var json = JsonSerializer.Serialize(requestBody);
    var content = new StringContent(json, Encoding.UTF8, "application/json");

    try
    {
        var response = await httpClient.PostAsync("/query", content);
        response.EnsureSuccessStatusCode();

        var responseBody = await response.Content.ReadAsStringAsync();
        var result = JsonSerializer.Deserialize<JsonElement>(responseBody);
        
        return result.GetProperty("response").GetString() ?? "No response from agent.";
    }
    catch (HttpRequestException ex)
    {
        return $"Error calling LangChain agent: {ex.Message}. Ensure the Python service is running on {langChainBaseUrl}";
    }
}

// ============================================================================
// ENDPOINTS
// ============================================================================

// Health check endpoint
app.MapGet("/health", () => Results.Ok(new
{
    status = "healthy",
    service = "DemoHost",
    langChainEndpoint = langChainBaseUrl,
    timestamp = DateTime.UtcNow
}));

// OpenAI-compatible chat completions endpoint
// This is what GitHub Copilot / MCP will call
app.MapPost("/chat/completions", async (HttpContext context, IHttpClientFactory clientFactory) =>
{
    try
    {
        // Parse the incoming request
        var requestBody = await JsonSerializer.DeserializeAsync<JsonElement>(context.Request.Body);
        
        // Extract the user's message (last message in the conversation)
        var messages = requestBody.GetProperty("messages").EnumerateArray().ToList();
        var lastMessage = messages.Last();
        var userQuery = lastMessage.GetProperty("content").GetString() ?? "";

        app.Logger.LogInformation("Received query: {Query}", userQuery);

        // Call the LangChain agent
        var httpClient = clientFactory.CreateClient("LangChainAgent");
        var agentResponse = await CallLangChainAgentAsync(httpClient, userQuery);

        app.Logger.LogInformation("Agent response: {Response}", agentResponse);

        // Return in OpenAI chat completion format
        var response = new
        {
            id = $"chatcmpl-{Guid.NewGuid()}",
            @object = "chat.completion",
            created = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            model = "support-agent",
            choices = new[]
            {
                new
                {
                    index = 0,
                    message = new
                    {
                        role = "assistant",
                        content = agentResponse
                    },
                    finish_reason = "stop"
                }
            },
            usage = new
            {
                prompt_tokens = userQuery.Length / 4,  // Rough estimate
                completion_tokens = agentResponse.Length / 4,
                total_tokens = (userQuery.Length + agentResponse.Length) / 4
            }
        };

        return Results.Ok(response);
    }
    catch (Exception ex)
    {
        app.Logger.LogError(ex, "Error processing chat completion request");
        return Results.Problem(
            detail: ex.Message,
            statusCode: 500,
            title: "Internal Server Error"
        );
    }
});

// Simple query endpoint (alternative to OpenAI format)
app.MapPost("/query", async (QueryRequest request, IHttpClientFactory clientFactory) =>
{
    var httpClient = clientFactory.CreateClient("LangChainAgent");
    var response = await CallLangChainAgentAsync(httpClient, request.Query);
    
    return Results.Ok(new QueryResponse
    {
        Query = request.Query,
        Response = response,
        Timestamp = DateTime.UtcNow
    });
});

// ============================================================================
// START THE APPLICATION
// ============================================================================

app.Logger.LogInformation("🚀 DemoHost starting on {Urls}", string.Join(", ", app.Urls));
app.Logger.LogInformation("📡 LangChain agent endpoint: {Endpoint}", langChainBaseUrl);
app.Logger.LogInformation("💡 Try: POST http://localhost:8080/query with {{ \"query\": \"Summarize ticket #42\" }}");

app.Run();

// ============================================================================
// REQUEST/RESPONSE MODELS
// ============================================================================

public record QueryRequest
{
    public required string Query { get; init; }
}

public record QueryResponse
{
    public required string Query { get; init; }
    public required string Response { get; init; }
    public DateTime Timestamp { get; init; }
}
