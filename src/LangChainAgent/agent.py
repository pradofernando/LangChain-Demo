"""
LangChain-style Support Agent for Microsoft Foundry demo.

Architecture decision: we use LangChain's `@tool` abstraction to define the
tool surface, but we drive the agent loop directly with the OpenAI SDK
(supports Azure OpenAI / Foundry deployments). This avoids the `tiktoken`
Rust-build dependency that ships with `langchain-openai` and isn't available
on Windows ARM64.

Three runtime modes (auto-selected by environment):
  1. Foundry / Azure OpenAI  — AZURE_OPENAI_ENDPOINT + DEPLOYMENT + API_KEY
  2. Direct OpenAI           — OPENAI_API_KEY
  3. Demo mock               — no env vars (canned responses)
"""

from __future__ import annotations

import json
import os
import re
from typing import Any, Callable

# Optional .env loading
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# LangChain @tool decorator (pure Python — safe on ARM64)
try:
    from langchain_core.tools import tool  # type: ignore[assignment]
    LANGCHAIN_AVAILABLE = True
except ImportError:
    LANGCHAIN_AVAILABLE = False

    def tool(func):  # type: ignore[no-redef]
        return func

# OpenAI SDK (pure Python)
try:
    from openai import OpenAI, AzureOpenAI
    OPENAI_SDK_AVAILABLE = True
except ImportError:
    OPENAI_SDK_AVAILABLE = False
    OpenAI = None  # type: ignore[assignment,misc]
    AzureOpenAI = None  # type: ignore[assignment,misc]


# Lightweight Entra ID (Azure AD) token provider that shells out to the Azure CLI.
# This avoids `azure-identity` which transitively requires `cryptography`
# (Rust + MSVC). Works as long as the user has run `az login`.
import json as _json
import subprocess
import threading
import time as _time

_AZ_TOKEN_LOCK = threading.Lock()
_AZ_TOKEN_CACHE: dict = {"token": None, "expires_on": 0.0}


def _get_az_cli_token(resource: str = "https://cognitiveservices.azure.com") -> str:
    """Return a bearer token for `resource`, cached until ~5 minutes before expiry."""
    now = _time.time()
    with _AZ_TOKEN_LOCK:
        if _AZ_TOKEN_CACHE["token"] and _AZ_TOKEN_CACHE["expires_on"] - now > 300:
            return _AZ_TOKEN_CACHE["token"]

        # `az` is a .cmd shim on Windows — shell=True keeps it simple.
        result = subprocess.run(
            f'az account get-access-token --resource "{resource}" -o json',
            capture_output=True,
            text=True,
            shell=True,
            timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(
                "Failed to acquire Entra ID token via `az account get-access-token`. "
                "Make sure the Azure CLI is installed and you have run `az login`. "
                f"stderr: {result.stderr.strip()}"
            )
        data = _json.loads(result.stdout)
        token = data["accessToken"]
        # expiresOn is "YYYY-MM-DD HH:MM:SS.ffffff"; fall back to now+50 min if parsing fails.
        try:
            from datetime import datetime
            exp = datetime.strptime(data["expiresOn"], "%Y-%m-%d %H:%M:%S.%f").timestamp()
        except Exception:
            exp = now + 50 * 60
        _AZ_TOKEN_CACHE["token"] = token
        _AZ_TOKEN_CACHE["expires_on"] = exp
        return token


# ============================================================================
# MOCK DATA: Support Tickets
# ============================================================================

MOCK_TICKETS = {
    "42": {
        "id": "42",
        "title": "Database connection timeout in production",
        "priority": "High",
        "status": "Open",
        "description": "Production database experiencing intermittent connection timeouts during peak hours. Users reporting slow page loads and occasional 504 errors.",
        "created": "2026-04-25T10:30:00Z",
        "reporter": "ops-team@company.com",
        "tags": ["database", "performance", "production"],
    },
    "101": {
        "id": "101",
        "title": "User cannot reset password",
        "priority": "Medium",
        "status": "In Progress",
        "description": "User reports that password reset email is not being received. Checked spam folder, issue persists.",
        "created": "2026-04-26T14:15:00Z",
        "reporter": "support@company.com",
        "tags": ["authentication", "email", "user-issue"],
    },
    "78": {
        "id": "78",
        "title": "Mobile app crashes on iOS 17",
        "priority": "Critical",
        "status": "Open",
        "description": "Multiple reports of app crashing immediately after launch on iOS 17.4. Issue does not occur on iOS 16 or earlier.",
        "created": "2026-04-27T09:00:00Z",
        "reporter": "mobile-team@company.com",
        "tags": ["mobile", "ios", "crash", "critical"],
    },
}


# ============================================================================
# TOOLS — defined with LangChain's @tool decorator
# ============================================================================

@tool
def get_ticket_details(ticket_id: str) -> str:
    """Fetch details for a support ticket by ID. Returns ticket info or an error."""
    ticket = MOCK_TICKETS.get(str(ticket_id).lstrip("#"))
    if not ticket:
        return f"Error: Ticket #{ticket_id} not found. Available tickets: {', '.join(MOCK_TICKETS.keys())}"
    return (
        f"Ticket #{ticket['id']}: {ticket['title']}\n"
        f"Priority: {ticket['priority']} | Status: {ticket['status']}\n"
        f"Created: {ticket['created']} | Reporter: {ticket['reporter']}\n\n"
        f"Description:\n{ticket['description']}\n\n"
        f"Tags: {', '.join(ticket['tags'])}"
    )


def _invoke_tool(tool_obj, args: dict) -> str:
    """Call a LangChain @tool object or a plain function with kwargs."""
    if hasattr(tool_obj, "invoke"):
        return tool_obj.invoke(args)
    return tool_obj(**args)


TOOL_REGISTRY: dict[str, Any] = {
    "get_ticket_details": get_ticket_details,
}

# OpenAI / Azure tool schema (function calling)
OPENAI_TOOLS_SCHEMA = [
    {
        "type": "function",
        "function": {
            "name": "get_ticket_details",
            "description": "Fetch details for a support ticket by ID (e.g. '42', '101', '78').",
            "parameters": {
                "type": "object",
                "properties": {
                    "ticket_id": {
                        "type": "string",
                        "description": "The numeric ticket ID, e.g. '42'.",
                    }
                },
                "required": ["ticket_id"],
            },
        },
    }
]

SYSTEM_PROMPT = (
    "You are a helpful support-ticket analyst. When asked about a ticket, use the "
    "`get_ticket_details` tool to fetch its data, then return a concise structured "
    "response containing: a one-line summary, priority/status, the issue description, "
    "and 4–6 actionable next steps tailored to the issue. Use Markdown."
)


# ============================================================================
# AGENT
# ============================================================================

class SupportAgent:
    """Minimal LangChain-style agent driven directly by the OpenAI SDK."""

    def __init__(self, client, model: str, mode: str):
        self.client = client
        self.model = model
        self.mode = mode  # "foundry" or "openai"

    def invoke(self, payload: dict[str, Any]) -> dict[str, str]:
        query = payload.get("input", "")
        messages: list[dict[str, Any]] = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": query},
        ]

        for _ in range(5):  # up to 5 tool-calling rounds
            resp = self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                tools=OPENAI_TOOLS_SCHEMA,
                temperature=0.3,
            )
            msg = resp.choices[0].message

            if not msg.tool_calls:
                return {"output": msg.content or ""}

            messages.append({
                "role": "assistant",
                "content": msg.content or "",
                "tool_calls": [
                    {
                        "id": tc.id,
                        "type": "function",
                        "function": {"name": tc.function.name, "arguments": tc.function.arguments},
                    }
                    for tc in msg.tool_calls
                ],
            })

            for tc in msg.tool_calls:
                fn_name = tc.function.name
                try:
                    args = json.loads(tc.function.arguments or "{}")
                except json.JSONDecodeError:
                    args = {}

                tool_obj = TOOL_REGISTRY.get(fn_name)
                if tool_obj is None:
                    result = f"Error: tool '{fn_name}' not found"
                else:
                    try:
                        result = _invoke_tool(tool_obj, args)
                    except Exception as e:  # noqa: BLE001
                        result = f"Tool error: {e}"

                messages.append({
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": str(result),
                })

        return {"output": "Agent stopped after 5 tool-call iterations."}


def create_support_agent():
    """Create the agent based on available env vars. Returns None for demo/mock mode."""
    if not OPENAI_SDK_AVAILABLE or OpenAI is None or AzureOpenAI is None:
        return None

    azure_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
    azure_deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT")
    azure_key = os.getenv("AZURE_OPENAI_API_KEY")
    azure_use_entra = os.getenv("AZURE_OPENAI_USE_ENTRA_ID", "").lower() in ("1", "true", "yes")
    openai_key = os.getenv("OPENAI_API_KEY")
    api_version = os.getenv("AZURE_OPENAI_API_VERSION", "2024-08-01-preview")

    if azure_endpoint and azure_deployment:
        # Prefer Entra ID when explicitly requested OR when no key is provided.
        prefer_entra = azure_use_entra or not azure_key

        if prefer_entra:
            # Token provider: callable returning a fresh bearer token on each call.
            def _token_provider() -> str:
                return _get_az_cli_token("https://cognitiveservices.azure.com")

            client = AzureOpenAI(
                azure_endpoint=azure_endpoint,
                azure_ad_token_provider=_token_provider,
                api_version=api_version,
            )
            return SupportAgent(client=client, model=azure_deployment, mode="foundry")

        if azure_key:
            client = AzureOpenAI(
                azure_endpoint=azure_endpoint,
                api_key=azure_key,
                api_version=api_version,
            )
            # For Azure OpenAI, "model" must be the deployment name
            return SupportAgent(client=client, model=azure_deployment, mode="foundry")

    if openai_key:
        client = OpenAI(api_key=openai_key)
        return SupportAgent(
            client=client,
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            mode="openai",
        )

    return None


def format_agent_response(agent_output: dict) -> str:
    return agent_output.get("output") or str(agent_output)


# ============================================================================
# MOCK RESPONSE (used when no credentials are configured)
# ============================================================================

def generate_mock_response(query: str) -> str:
    ticket_match = re.search(r"#?(\d+)", query)
    ticket_id = ticket_match.group(1) if ticket_match else None

    if ticket_id and ticket_id in MOCK_TICKETS:
        ticket = MOCK_TICKETS[ticket_id]
        recs_by_kind = {
            "database": [
                "Check database connection pool settings and increase if needed",
                "Review database query performance and optimize slow queries",
                "Monitor database server resource utilization (CPU, memory, disk I/O)",
                "Check for long-running transactions or locks",
                "Implement connection retry logic with exponential backoff",
                "Scale database tier if resource constraints are identified",
            ],
            "password": [
                "Verify email service is operational and not rate-limited",
                "Check spam/blocklist status of sending domain",
                "Review password reset token generation and expiration logic",
                "Test email delivery to multiple providers",
                "Confirm user's email address in the system",
                "Provide alternative reset method (security questions, admin reset)",
            ],
            "ios": [
                "Collect crash logs and stack traces from affected devices",
                "Test on physical iOS 17.4 devices",
                "Review recent code changes related to app initialization",
                "Check for iOS 17-specific API deprecations",
                "Implement crash reporting (e.g., Firebase Crashlytics)",
                "Roll back to previous version if widespread; fast-track patch",
            ],
        }
        title = ticket["title"].lower()
        if "database" in title or "timeout" in title:
            recs = recs_by_kind["database"]
        elif "password" in title or "reset" in title:
            recs = recs_by_kind["password"]
        elif "crash" in title or "ios" in title:
            recs = recs_by_kind["ios"]
        else:
            recs = [
                "Gather more information from the reporter",
                "Reproduce the issue in a test environment",
                "Check logs for related errors or warnings",
                "Identify recent changes that could be the cause",
                "Assign to the appropriate team",
            ]

        recs_md = "\n".join(f"{i+1}. {r}" for i, r in enumerate(recs))
        return (
            f"**Ticket #{ticket['id']} Analysis**\n\n"
            f"**Summary:** {ticket['title']}\n"
            f"Priority: {ticket['priority']} | Status: {ticket['status']}\n\n"
            f"**Issue Description:**\n{ticket['description']}\n\n"
            f"**Recommended Next Steps:**\n{recs_md}\n\n"
            f"**Tags:** {', '.join(ticket['tags'])}\n"
            f"**Created:** {ticket['created']}"
        )

    return (
        "I'm a support-ticket analysis agent.\n\n"
        "Try asking about tickets **#42**, **#101**, or **#78** "
        "(e.g. *\"Summarize ticket #42 and suggest next steps\"*).\n\n"
        "_Demo mode_ — set `AZURE_OPENAI_*` env vars to use a Foundry-deployed model."
    )
