# DEMO SCRIPT: Hosting a LangChain Agent in Microsoft Foundry with GitHub Copilot

**Duration:** 15 minutes  
**Presenter Prep:** 5 minutes (run `.\scripts\run-local.ps1` before demo)  
**Audience:** Developers interested in AI agents, Azure, and Copilot extensibility

---

## Setup Checklist (Before Demo Starts)

- [ ] Run `.\scripts\run-local.ps1` — both services should be running
- [ ] Open VS Code with GitHub Copilot enabled
- [ ] Have both `src/DemoHost/Program.cs` and `src/LangChainAgent/agent.py` open in tabs
- [ ] Terminal window ready for showing `test-demo.ps1`
- [ ] Browser tab open to Azure Portal (Foundry resource view)

**Note:** The demo works without OpenAI API keys (uses intelligent mock responses). For full LangChain agent, set `OPENAI_API_KEY` environment variable before starting.

---

## Minute 0-3: Introduction & Problem Statement

### What to Say

> "Today I'm showing you how to host a **LangChain agent** in **Microsoft Foundry** and call it directly from **GitHub Copilot** in your editor."
>
> **The Challenge:** You've built an intelligent agent using LangChain, but now you need to:
> 1. Host it reliably in Azure
> 2. Make it accessible to your developers through Copilot
> 3. Keep the architecture Microsoft-native for enterprise compliance
>
> **The Solution:** A simple pattern using .NET as the orchestration layer, LangChain for agent logic, Foundry for hosting, and MCP for Copilot integration."

### What to Show

- **Architecture diagram** from README.md
- Point out the four layers: Copilot → Foundry → .NET → LangChain

**Time Check:** 3 minutes elapsed

---

## Minute 3-6: Show the LangChain Agent

### What to Say

> "Let's start with the LangChain agent. This is a simple ReAct agent with one tool: looking up support ticket details."

### What to Show

1. Open [src/LangChainAgent/agent.py](src/LangChainAgent/agent.py)
2. **Highlight the tool function:**
   ```python
   @tool
   def get_ticket_details(ticket_id: str) -> str:
       """Fetch details for a support ticket by ID."""
   ```

3. **Highlight the agent creation:**
   ```python
   agent = create_react_agent(llm, tools, prompt)
   ```

4. **Mention the FastAPI wrapper:**
   ```python
   @app.post("/query")
   async def query_agent(request: QueryRequest):
   ```

### What to Say

> "The agent receives a query, decides if it needs to call tools, and returns a structured response. We expose this via a simple FastAPI endpoint on port 8000."

**Time Check:** 6 minutes elapsed

---

## Minute 6-9: Show the .NET Host

### What to Say

> "Now let's look at the .NET host. This is where Microsoft frameworks shine."

### What to Show

1. Open [src/DemoHost/Program.cs](src/DemoHost/Program.cs)

2. **Highlight Semantic Kernel setup:**
   ```csharp
   var kernel = Kernel.CreateBuilder()
       .AddOpenAIChatCompletion("gpt-4", "your-api-key")
       .Build();
   ```

3. **Highlight the LangChain skill registration:**
   ```csharp
   // Register LangChain agent as a Semantic Kernel function
   var langChainFunction = kernel.CreateFunctionFromPrompt(
       "Query the LangChain agent: {{$input}}",
       new() { Temperature = 0.7 }
   );
   ```

4. **Highlight the minimal API endpoint:**
   ```csharp
   app.MapPost("/chat/completions", async (ChatRequest request) =>
   {
       var response = await kernel.InvokeAsync(langChainFunction, 
           new() { ["input"] = request.Messages.Last().Content });
       return Results.Ok(new { response.Result });
   });
   ```

### What to Say

> "The .NET host does three things:
> 1. Wraps the LangChain endpoint as a Semantic Kernel function
> 2. Exposes an OpenAI-compatible API
> 3. Handles auth, logging, and error handling for production
>
> This keeps the Python agent simple and the .NET layer handles all Azure integration."

**Time Check:** 9 minutes elapsed

---

## Minute 9-11: Run the Demo Locally

### What to Say

> "Let's see it in action locally before we deploy to Foundry."

### What to Show

1. Switch to terminal
2. Run `.\scripts\test-demo.ps1`
3. **Show the output:**
   - Request to .NET host
   - Call to LangChain agent
   - Tool execution (ticket lookup)
   - Final response

### Terminal Output (Expected)

```
Testing LangChain → .NET Host integration...

Request: Summarize ticket #42 and suggest next steps
Response: 
  Ticket #42: "Database connection timeout in prod"
  Priority: High
  
  Summary: Production database experiencing intermittent connection timeouts...
  
  Suggested Next Steps:
  1. Check connection pool settings
  2. Review database logs for errors
  3. Monitor network latency
  4. Consider scaling database tier
```

### What to Say

> "Perfect! The agent looked up ticket #42, analyzed it, and gave us actionable recommendations. All running locally on our laptop."

**Time Check:** 11 minutes elapsed

---

## Minute 11-13: Deploy to Microsoft Foundry

### What to Say

> "Now let's deploy this to Foundry so it's accessible to our entire team through Copilot."

### What to Show

1. Open [foundry/agent.yaml](foundry/agent.yaml)

2. **Highlight the deployment manifest:**
   ```yaml
   name: support-agent
   description: "Analyzes support tickets and suggests next steps"
   containers:
     - name: dotnet-host
       image: {{REGISTRY}}/support-agent-host:latest
       port: 8080
     - name: langchain-agent
       image: {{REGISTRY}}/langchain-agent:latest
       port: 8000
   ```

3. **Show deployment command** (don't run during demo):
   ```powershell
   az foundry agent create --config ./foundry/agent.yaml
   ```

4. **Switch to browser** → Azure Portal → Foundry resource
5. **Show the deployed agent** with its endpoint URL

### What to Say

> "Foundry handles the container orchestration, networking, and scaling. We get a single HTTPS endpoint that's production-ready."

**Time Check:** 13 minutes elapsed

---

## Minute 13-15: GitHub Copilot Integration & Wrap-Up

### What to Say

> "Now for the magic: calling this from GitHub Copilot in VS Code."

### What to Show

1. Open [.vscode/mcp.json](.vscode/mcp.json)

2. **Highlight the MCP configuration:**
   ```json
   {
     "servers": {
       "support-agent": {
         "endpoint": "https://your-foundry-endpoint.azurewebsites.net",
         "description": "Support ticket analysis agent"
       }
     }
   }
   ```

3. **Open Copilot Chat in VS Code**

4. **Type the prompt:**
   ```
   @support-agent Summarize ticket #42 and suggest next steps
   ```

5. **Show the response appearing in Copilot Chat**

### What to Say

> "Our developers can now analyze tickets, get recommendations, and take action without leaving their editor.
>
> **Recap:**
> - ✅ LangChain agent for AI logic
> - ✅ .NET host for Azure integration
> - ✅ Foundry for reliable hosting
> - ✅ MCP for seamless Copilot access
>
> **Next steps you can take:**
> 1. Add your own tools to the LangChain agent
> 2. Integrate with your ticketing system
> 3. Add authentication and monitoring
> 4. Scale to multiple agents for different domains
>
> The repo is ready to clone and run. Questions?"

**Time Check:** 15 minutes elapsed

---

## Q&A Preparation

### Common Questions

**Q: Why not just use .NET for everything?**  
A: LangChain has the richest ecosystem of pre-built tools and integrations. This pattern lets you leverage that while keeping Azure integration clean.

**Q: Can I use this with Azure OpenAI instead of OpenAI?**  
A: Yes! Just update the Semantic Kernel configuration to use `AddAzureOpenAIChatCompletion()`.

**Q: What about authentication?**  
A: Foundry supports Azure AD/Entra ID out of the box. Add `authentication` to `agent.yaml` and configure in the portal.

**Q: Does this work with other LLM providers?**  
A: Yes. Semantic Kernel supports multiple providers (Azure OpenAI, OpenAI, Hugging Face). LangChain supports 50+ model providers.

**Q: How much does Foundry cost?**  
A: Foundry pricing is based on compute time and requests. For this demo-sized workload, expect $10-50/month depending on usage.

---

## Backup Slides / Talking Points

If you finish early or need to fill time:

1. **Show the Dockerfile** for containerization
2. **Walk through error handling** in Program.cs
3. **Demonstrate monitoring** in Azure Portal
4. **Show the CI/CD pipeline** (if configured)
5. **Compare to other hosting options** (AKS, Container Apps, App Service)

---

## Technical Notes for Presenter

- **If local demo fails:** Have a pre-recorded video or deployed version as backup
- **If Copilot fails:** Fall back to `curl` or Postman to show the raw API
- **If questions run long:** Skip the deployment section and show deployed version only
- **If ahead of time:** Add a 2-minute section on customizing tools or agents

---

## Materials to Share After Demo

- GitHub repository link
- Link to Microsoft Foundry docs: https://aka.ms/foundry
- Link to Semantic Kernel samples: https://github.com/microsoft/semantic-kernel
- Link to LangChain docs: https://python.langchain.com
- Your contact info for follow-up questions
