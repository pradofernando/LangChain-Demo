# Hosting a LangChain Agent in Microsoft Foundry with GitHub Copilot

> A small reference project showing how to keep your existing **LangChain** agents and bring them onto the **Microsoft AI stack** — a .NET minimal API + Semantic Kernel host, a model deployed in **Microsoft Foundry**, a simple web frontend, and **MCP** integration so **GitHub Copilot** can call the agent directly from VS Code Chat.

[![.NET](https://img.shields.io/badge/.NET-9.0-512BD4?logo=dotnet)](https://dotnet.microsoft.com/)
[![Python](https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![LangChain](https://img.shields.io/badge/LangChain-agent-1C3C3C)](https://www.langchain.com/)
[![Microsoft Foundry](https://img.shields.io/badge/Microsoft-Foundry-0078D4)](https://aka.ms/foundry)
[![MCP](https://img.shields.io/badge/MCP-GitHub%20Copilot-181717?logo=github)](https://modelcontextprotocol.io/)

---

## Why this project exists

A common question: *"I already have agents written in LangChain — do I have to rewrite them to use Microsoft Foundry, Semantic Kernel, or Copilot?"*

**No.** This repo shows a tiny end-to-end pattern where:

- The **agent logic stays in Python/LangChain**.
- A thin **.NET minimal API** (with Semantic Kernel) wraps it and exposes Microsoft-native, OpenAI-compatible endpoints.
- The agent's "brain" is a **chat model deployed in Microsoft Foundry** (Azure OpenAI under the hood).
- A **simple web frontend** is served straight from the .NET host so anyone can try it.
- A **`mcp.json`** lets GitHub Copilot call the agent natively from VS Code Chat.

It's intentionally kept small — every file is short and readable, so it works as both a runnable example and a starting point you can fork.

---

## Architecture

```
                ┌──────────────────────────┐
                │  GitHub Copilot          │
                │  (VS Code Chat)          │
                └─────────────┬────────────┘
                              │ MCP (.vscode/mcp.json)
                              ▼
┌────────────────────────────────────────────────────────────┐
│  .NET 9 Minimal API   (port 8080)                          │
│  ─ Semantic Kernel orchestration                           │
│  ─ Static frontend  (wwwroot/index.html)                   │
│  ─ /chat/completions  (OpenAI-compatible, for MCP/Copilot) │
│  ─ /query            (simple JSON endpoint, for the UI)    │
└─────────────┬──────────────────────────────────────────────┘
              │ HTTP
              ▼
┌────────────────────────────────────────────────────────────┐
│  Python FastAPI + LangChain agent  (port 8000)             │
│  ─ @tool get_ticket_details                                │
│  ─ Tool-calling loop driven by the OpenAI SDK              │
└─────────────┬──────────────────────────────────────────────┘
              │ HTTPS
              ▼
┌────────────────────────────────────────────────────────────┐
│  Microsoft Foundry — chat model deployment                 │
│  (e.g. gpt-4o-mini)                                        │
└────────────────────────────────────────────────────────────┘
```

### Components

| Component | Tech | Purpose |
|---|---|---|
| **Web frontend** | Vanilla HTML/JS | Chat UI served by the .NET host at `/` |
| **.NET host** | ASP.NET Core 9 + Semantic Kernel | API gateway, OpenAI-compatible endpoint, static file server |
| **LangChain agent** | Python 3.11+ / FastAPI | Agent logic, tools, model orchestration |
| **Model** | Azure OpenAI / Foundry | The LLM that powers the agent (`gpt-4o-mini` recommended) |
| **MCP config** | [.vscode/mcp.json](.vscode/mcp.json) | Lets GitHub Copilot call the agent |
| **Foundry manifest** | [foundry/agent.yaml](foundry/agent.yaml) | Optional: deploy both containers to Foundry |

### Why this split?

- **Python keeps the LangChain ecosystem** — no rewrite needed.
- **.NET is the customer-facing surface** — easy to integrate with Azure AD, App Service, Container Apps, Foundry, and Semantic Kernel skills.
- **Foundry hosts the model only** — your agent code stays portable; only the LLM call goes to Azure.
- **MCP is configuration-only** — Copilot integration is a JSON file, no extension required.

---

## What runs out of the box

Three runtime modes, picked automatically based on environment variables:

| Mode | Trigger | Uses |
|---|---|---|
| **Foundry** ⭐ | `AZURE_OPENAI_ENDPOINT` + `AZURE_OPENAI_DEPLOYMENT` + `AZURE_OPENAI_API_KEY` set | Real Azure OpenAI / Foundry-deployed model |
| **OpenAI direct** | `OPENAI_API_KEY` set | OpenAI public API |
| **Mock** | nothing set | Hard-coded, ticket-aware canned responses (perfect for offline trials) |

You can clone the repo and run it with **zero credentials** in mock mode, or wire in a Foundry model with three env vars.

---

## Example scenario — Support Ticket Triage

The agent has one tool, `get_ticket_details(ticket_id)`, backed by a small in-memory dataset of three tickets:

| Ticket | Title | Priority |
|---|---|---|
| **#42** | Database connection timeout in production | High |
| **#101** | User cannot reset password | Medium |
| **#78** | Mobile app crashes on iOS 17 | Critical |

When you ask *"Summarize ticket #42 and suggest next steps"*, the model:

1. Calls the `get_ticket_details` tool with `ticket_id="42"`.
2. Receives the structured ticket data back.
3. Returns a markdown report with summary, priority, description, and 4–6 tailored remediation steps.

The same flow works from the **web UI**, the **`/query` API**, and **GitHub Copilot Chat** via MCP.

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| **.NET SDK** | 9.0+ | `dotnet --version` to confirm |
| **Python** | 3.11+ (3.13 tested) | `python --version` |
| **PowerShell** | 7+ | The start scripts are `.ps1` |
| **VS Code** + GitHub Copilot | latest | For the MCP integration step |
| **Microsoft Foundry project** | — | Optional but recommended (otherwise runs in mock mode) |
| **Docker Desktop** | optional | Only needed if you also deploy to Foundry as containers |

> **Windows ARM64 note:** This project intentionally avoids Python packages that need a Rust/C++ toolchain (`tiktoken`, `numpy`, etc.). Everything in [requirements.txt](src/LangChainAgent/requirements.txt) is pure Python and installs cleanly on ARM64.

---

## Quick start (local, ~5 minutes)

### 1. Clone

```powershell
git clone https://github.com/pradofernando/LangChain-Demo.git
cd LangChain-Demo
```

### 2. (Optional) Wire up your Foundry model

Skip this whole step to run in mock mode.

1. In your **Microsoft Foundry** project → **Models + endpoints** → deploy a chat model that supports tool/function calling, e.g. `gpt-4o-mini`.
2. Copy `.env.example` → `.env`, then fill in:

   ```ini
   AZURE_OPENAI_ENDPOINT=https://<your-resource>.openai.azure.com/
   AZURE_OPENAI_DEPLOYMENT=gpt-4o-mini
   AZURE_OPENAI_API_KEY=<your-key>
   AZURE_OPENAI_API_VERSION=2024-08-01-preview
   ```

   `AZURE_OPENAI_DEPLOYMENT` is the **deployment name** you chose, not the underlying model name.

   `.env` is gitignored, so it stays on your machine.

### 3. Run it (two terminals)

**Terminal 1 — LangChain agent:**

```powershell
.\scripts\start-langchain.ps1
```

This installs Python dependencies (idempotent), loads `.env`, and starts FastAPI on `http://localhost:8000`.

**Terminal 2 — .NET host + web frontend:**

```powershell
.\scripts\start-dotnet.ps1
```

This restores, builds, and starts ASP.NET Core on `http://localhost:8080`.

### 4. Try it

| Surface | URL / Command |
|---|---|
| 🌐 **Web UI** | Open <http://localhost:8080> in your browser |
| 🔧 **API (simple)** | `POST http://localhost:8080/query` with `{"query":"Summarize ticket #42"}` |
| 🤖 **API (OpenAI-compatible)** | `POST http://localhost:8080/chat/completions` with a `messages` array |
| ✨ **GitHub Copilot** | In VS Code Chat: `@support-agent Summarize ticket #42` |
| ❤️ **Health** | `GET http://localhost:8080/health` |

---

## Project structure

```
LangChain-Demo/
├── .github/agents/
│   └── langchain-foundry-demo.agent.md   # Custom VS Code agent definition
├── .vscode/
│   └── mcp.json                          # GitHub Copilot ↔ agent wiring (MCP)
├── src/
│   ├── DemoHost/                         # .NET 9 minimal API
│   │   ├── Program.cs                    # All endpoints + static file middleware
│   │   ├── DemoHost.csproj               # Semantic Kernel + HTTP packages
│   │   ├── appsettings.json
│   │   ├── Dockerfile                    # For Foundry / Container Apps
│   │   └── wwwroot/
│   │       └── index.html                # Self-contained chat frontend
│   └── LangChainAgent/                   # Python FastAPI service
│       ├── main.py                       # FastAPI app + /health, /query
│       ├── agent.py                      # @tool definition + agent loop
│       ├── requirements.txt              # Pure-Python deps only (ARM64-safe)
│       └── Dockerfile
├── foundry/
│   └── agent.yaml                        # Foundry deployment manifest (sidecar pattern)
├── scripts/
│   ├── start-langchain.ps1               # Terminal 1
│   ├── start-dotnet.ps1                  # Terminal 2
│   ├── run-local.ps1                     # Experimental one-shot launcher
│   └── test-demo.ps1                     # Integration test (5 cases)
├── .env.example                          # Foundry env-var template
├── .gitignore                            # Excludes .env, build outputs, etc.
└── README.md                             # ← you are here
```

---

## How the pieces fit together

### The .NET host ([src/DemoHost/Program.cs](src/DemoHost/Program.cs))

- A single-file ASP.NET Core 9 minimal API.
- Registers a typed `HttpClient` for the Python service.
- `app.UseDefaultFiles()` + `app.UseStaticFiles()` serves [wwwroot/index.html](src/DemoHost/wwwroot/index.html) at `/`.
- Three endpoints:
  - `GET /health` — service status + LangChain endpoint
  - `POST /query` — simple `{query, response, timestamp}` shape (used by the UI)
  - `POST /chat/completions` — OpenAI-compatible (used by MCP/Copilot)
- Semantic Kernel is wired in the DI container so it can be extended with native skills, plugins, or chat history later.

### The LangChain agent ([src/LangChainAgent/agent.py](src/LangChainAgent/agent.py))

- One LangChain `@tool` (`get_ticket_details`) — easy to swap for a real backend.
- A **minimal agent loop** built on top of the OpenAI SDK that:
  1. Sends the user query + system prompt + tool schemas.
  2. If the model emits `tool_calls`, dispatches to the LangChain `@tool` and feeds results back.
  3. Loops up to 5 times until the model returns a final answer.
- Auto-detects Foundry vs. OpenAI vs. mock mode based on env vars.

> **Why not `langchain-openai` directly?** It pulls in `tiktoken`, which requires a Rust toolchain — not available on Windows ARM64 by default. We keep the LangChain *abstractions* (tools, prompts) and use the pure-Python OpenAI SDK for the model call. Same architecture, broader portability.

### The web frontend ([src/DemoHost/wwwroot/index.html](src/DemoHost/wwwroot/index.html))

- ~200 lines of vanilla HTML/CSS/JS — no build step, no framework.
- Live status indicator (polls `/health`).
- Click-to-send example prompts.
- Calls `/query` and renders responses with whitespace preserved.

### MCP configuration ([.vscode/mcp.json](.vscode/mcp.json))

- Points Copilot at `http://localhost:8080`.
- Trigger phrases include "ticket", "support", "analyze ticket".
- After deploying to Foundry, change the URL and reload VS Code — Copilot now talks to production.

---

## Going to production with Foundry

This project runs locally; the path to production is short:

1. **Deploy your model in Foundry** (already done if you followed Quick Start).
2. **Containerise both services** — Dockerfiles already in [src/DemoHost/Dockerfile](src/DemoHost/Dockerfile) and [src/LangChainAgent/Dockerfile](src/LangChainAgent/Dockerfile).
3. **Push to Azure Container Registry**.
4. **Apply [foundry/agent.yaml](foundry/agent.yaml)** — it deploys the .NET host + Python sidecar with managed identity, autoscaling (1–10 replicas), liveness/readiness probes, and Application Insights telemetry.
5. **Update [.vscode/mcp.json](.vscode/mcp.json)** to point at the public Foundry endpoint.

What you'd typically add for production (intentionally omitted to keep this small):
- Authentication (Entra ID / managed identity on the .NET host)
- Key Vault for `AZURE_OPENAI_API_KEY`
- App Insights tracing across the .NET → Python hop
- Real ticketing-system integration in `get_ticket_details` (Jira, ServiceNow, etc.)

---

## Extending it

- **Add a tool:** Define another `@tool` in [agent.py](src/LangChainAgent/agent.py), append its schema to `OPENAI_TOOLS_SCHEMA`, register in `TOOL_REGISTRY`. Done.
- **Swap the LLM:** Change the deployment in `.env` — no code changes needed.
- **Replace mock data:** Point `get_ticket_details` at your real ticketing API.
- **Add Semantic Kernel native skills:** Register them in `Program.cs` and have the .NET layer pre/post-process queries before forwarding.
- **Multi-agent:** Spin up additional Python services and route from the .NET host.

---

## Troubleshooting

<details>
<summary><b>Port already in use</b></summary>

```powershell
netstat -ano | findstr ":8000 :8080"
# Kill any orphaned processes:
Get-Process python, dotnet -ErrorAction SilentlyContinue | Stop-Process -Force
```
</details>

<details>
<summary><b>"You must install or update .NET 8.0"</b></summary>

The project targets .NET 9. If you see this error, you have an old `bin/` from before the upgrade — delete it:

```powershell
Remove-Item -Recurse -Force src\DemoHost\bin, src\DemoHost\obj
```
</details>

<details>
<summary><b>Python pip fails with <code>tiktoken</code> / Rust errors</b></summary>

Pull the latest [requirements.txt](src/LangChainAgent/requirements.txt) — packages that depend on `tiktoken` were removed to keep installs Windows-ARM64-friendly.
</details>

<details>
<summary><b>Agent says "DEMO MODE" instead of using my Foundry model</b></summary>

- Confirm `.env` exists in the repo root (not in `src/LangChainAgent/`).
- Restart Terminal 1 — env vars are loaded at startup.
- The startup log should say: <code>✅ Agent initialized successfully — using Azure OpenAI / Foundry (model: &lt;your-deployment&gt;)</code>.
</details>

<details>
<summary><b>Copilot doesn't see the <code>@support-agent</code></b></summary>

- Reload VS Code after editing [.vscode/mcp.json](.vscode/mcp.json).
- Confirm both services are running on the URL in `mcp.json`.
- Check the MCP server status in Copilot's chat input.
</details>

---

## Resources

- 🔌 [Microsoft Foundry docs](https://aka.ms/foundry)
- 🧠 [Semantic Kernel](https://learn.microsoft.com/semantic-kernel/)
- 🔗 [LangChain](https://www.langchain.com/)
- 🤝 [Model Context Protocol](https://modelcontextprotocol.io/)

---

## License

MIT — feel free to fork, adapt, and reuse.
