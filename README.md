# Hosting a LangChain Agent in Microsoft Foundry with GitHub Copilot

A 15-minute demo showing how to host a LangChain agent in Microsoft Foundry and call it from GitHub Copilot using a Microsoft-first architecture.

## Architecture

```
┌─────────────────────┐
│  GitHub Copilot     │  ← User interacts here
│  (VS Code Chat)     │
└──────────┬──────────┘
           │ MCP Protocol
           ▼
┌─────────────────────┐
│  Microsoft Foundry  │  ← Hosted in Azure
│  ┌─────────────────┐│
│  │ .NET Host API   ││  ← Semantic Kernel orchestration
│  │ (Port 8080)     ││
│  └────────┬────────┘│
│           │         │
│           ▼         │
│  ┌─────────────────┐│
│  │ LangChain Agent ││  ← Python ReAct agent
│  │ (Port 8000)     ││
│  └─────────────────┘│
└─────────────────────┘
```

### Components

1. **LangChain Agent** (Python/FastAPI)
   - Simple ReAct agent with a support ticket lookup tool
   - Receives queries and returns structured responses
   - Runs on port 8000

2. **.NET Host API** (ASP.NET Core Minimal API)
   - Uses **Semantic Kernel** for orchestration
   - Wraps the LangChain agent as a skill/function
   - Exposes OpenAI-compatible `/chat/completions` endpoint
   - Runs on port 8080

3. **Microsoft Foundry**
   - Hosts both services as containers
   - Provides managed endpoints and scaling
   - Integrates with Azure Monitor for observability

4. **GitHub Copilot Integration**
   - MCP (Model Context Protocol) configuration
   - Allows Copilot Chat to invoke the agent
   - Seamless in-editor experience

## Prerequisites

- **.NET 8.0 SDK** or later
- **Python 3.11+** with pip
- **Docker Desktop** (optional, for containerized testing)
- **Azure CLI** (optional, for Foundry deployment)
- **VS Code** with GitHub Copilot extension (for full demo)

**Note:** OpenAI API key is **optional** for local testing. The demo runs in mock mode without API credentials.

## Setup

### 1. Clone and Install

```powershell
# Clone the repository
git clone <your-repo-url>
cd "LangChain Demo"

# Install .NET dependencies
cd src/DemoHost
dotnet restore

# Install Python dependencies
cd ../LangChainAgent
pip install -r requirements.txt
```

### 2. Configure your Foundry-deployed model

1. Deploy a chat model in your **Microsoft Foundry** project (e.g. `gpt-4o-mini`).
2. Copy `.env.example` → `.env` and fill in:

   ```
   AZURE_OPENAI_ENDPOINT=https://<your-foundry>.openai.azure.com/
   AZURE_OPENAI_DEPLOYMENT=gpt-4o-mini
   AZURE_OPENAI_API_KEY=<your-key>
   AZURE_OPENAI_API_VERSION=2024-08-01-preview
   ```

The Python agent auto-loads `.env` at startup. If no creds are set, the agent
falls back to **mock mode** so the demo still works.

### 3. Run locally (two terminals)

**Terminal 1 — LangChain agent:**
```powershell
.\scripts\start-langchain.ps1
```

**Terminal 2 — .NET host + frontend:**
```powershell
.\scripts\start-dotnet.ps1
```

Then open **http://localhost:8080** in your browser to use the chat UI.

### 4. Demo flow

- **Web UI:** http://localhost:8080  (chat with the agent visually)
- **API:** `POST http://localhost:8080/query` with `{"query":"Summarize ticket #42"}`
- **GitHub Copilot:** open VS Code Chat and try `@support-agent Summarize ticket #42`

## Demo Scenario

**User prompt:** "Summarize support ticket #42 and suggest next steps."

**Agent flow:**
1. LangChain agent receives the request
2. Calls the `get_ticket_details` tool to fetch ticket data
3. Analyzes the ticket content
4. Returns a summary and actionable recommendations
5. Response flows back through .NET host → Foundry → Copilot → User

## Project Structure

```
LangChain Demo/
├── .github/agents/          # Custom Copilot agent definition
├── .vscode/
│   └── mcp.json            # MCP configuration for Copilot
├── src/
│   ├── DemoHost/           # .NET minimal API host
│   │   ├── Program.cs
│   │   ├── DemoHost.csproj
│   │   └── appsettings.json
│   └── LangChainAgent/     # Python LangChain service
│       ├── main.py
│       ├── agent.py
│       └── requirements.txt
├── foundry/
│   └── agent.yaml          # Foundry hosted agent manifest
├── scripts/
│   ├── run-local.ps1       # Local development runner
│   └── test-demo.ps1       # Integration test
├── README.md               # This file
└── DEMO.md                 # 15-minute presentation script
```

## Key Design Decisions

1. **Why .NET + Python?**
   - LangChain's strongest ecosystem is Python
   - .NET provides first-class Azure/Foundry integration
   - Keeps each component focused and simple

2. **Why Semantic Kernel?**
   - Native Microsoft framework for AI orchestration
   - Clean integration with Azure OpenAI and custom endpoints
   - Production-ready with strong typing

3. **Why MCP?**
   - Standardized protocol for Copilot extensions
   - Configuration-based, no code required
   - Easy to share and replicate

## Troubleshooting

### Port conflicts
```powershell
# Check ports 8000 and 8080
netstat -ano | findstr "8000"
netstat -ano | findstr "8080"
```

### Python dependencies
```powershell
cd src/LangChainAgent
pip install --upgrade -r requirements.txt
```

### .NET restore issues
```powershell
cd src/DemoHost
dotnet clean
dotnet restore --force
```

## Next Steps

- Review [DEMO.md](./DEMO.md) for the 15-minute presentation flow
- Customize the LangChain agent with your own tools
- Add authentication and monitoring for production use
- Explore [Microsoft Foundry documentation](https://aka.ms/foundry)

## License

MIT - See LICENSE file for details.
