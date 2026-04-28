"""
FastAPI wrapper for LangChain Support Agent

Exposes the agent via HTTP endpoints for the .NET host to call.
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import Optional
import os
import uvicorn
import logging
from agent import create_support_agent, format_agent_response, generate_mock_response

# ============================================================================
# LOGGING SETUP
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# ============================================================================
# FASTAPI APP
# ============================================================================

app = FastAPI(
    title="LangChain Support Agent",
    description="A simple ReAct agent for support ticket analysis",
    version="1.0.0"
)

# ============================================================================
# REQUEST/RESPONSE MODELS
# ============================================================================

class QueryRequest(BaseModel):
    """Request model for agent queries."""
    query: str = Field(..., description="The user's question or task")
    session_id: Optional[str] = Field(None, description="Optional session ID for conversation tracking")

class QueryResponse(BaseModel):
    """Response model for agent queries."""
    query: str
    response: str
    session_id: Optional[str] = None

class HealthResponse(BaseModel):
    """Health check response."""
    status: str
    service: str
    version: str

# ============================================================================
# AGENT INITIALIZATION
# ============================================================================

# Initialize agent on startup
agent_executor = None

@app.on_event("startup")
async def startup_event():
    """Initialize the agent when the service starts."""
    global agent_executor
    logger.info("🚀 Initializing LangChain support agent...")
    
    try:
        agent_executor = create_support_agent()
        if agent_executor is None:
            logger.warning("⚠️  Running in DEMO MODE")
            logger.warning("   No LangChain or no model credentials configured")
            logger.info("   Using intelligent mock responses for ticket analysis")
            logger.info("   To use a Foundry-deployed model, set:")
            logger.info("     AZURE_OPENAI_ENDPOINT=https://<your-foundry>.openai.azure.com/")
            logger.info("     AZURE_OPENAI_DEPLOYMENT=<your-deployment-name>")
            logger.info("     AZURE_OPENAI_API_KEY=<your-key>")
        else:
            mode = "Azure OpenAI / Foundry" if os.getenv("AZURE_OPENAI_ENDPOINT") else "OpenAI"
            logger.info(f"✅ Agent initialized successfully — using {mode} (model: {agent_executor.model})")
    except Exception as e:
        logger.error(f"❌ Failed to initialize agent: {e}")
        logger.warning("   Falling back to demo mode with mock responses")
        agent_executor = None

# ============================================================================
# ENDPOINTS
# ============================================================================

@app.get("/", tags=["Root"])
async def root():
    """Root endpoint with service information."""
    return {
        "service": "LangChain Support Agent",
        "version": "1.0.0",
        "status": "running",
        "endpoints": {
            "health": "/health",
            "query": "POST /query",
            "docs": "/docs"
        }
    }

@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """Health check endpoint."""
    # Always return healthy - we can run in demo mode
    return HealthResponse(
        status="healthy",
        service="LangChain Support Agent",
        version="1.0.0"
    )

@app.post("/query", response_model=QueryResponse, tags=["Agent"])
async def query_agent(request: QueryRequest):
    """
    Send a query to the LangChain agent.
    
    The agent will:
    1. Analyze the query
    2. Use tools if needed (e.g., fetch ticket details)
    3. Return a structured response with summary and recommendations
    
    If no OpenAI API key is configured, returns mock responses for demo purposes.
    """
    logger.info(f"📥 Received query: {request.query}")
    
    try:
        # Check if we have a real agent or use mock mode
        if agent_executor is not None:
            # Use real LangChain agent
            result = agent_executor.invoke({"input": request.query})
            response_text = format_agent_response(result)
        else:
            # Use mock responses for demo
            response_text = generate_mock_response(request.query)
        
        logger.info(f"📤 Agent response: {response_text[:100]}...")
        
        return QueryResponse(
            query=request.query,
            response=response_text,
            session_id=request.session_id
        )
    
    except Exception as e:
        logger.error(f"❌ Error processing query: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Error processing query: {str(e)}"
        )

# ============================================================================
# MAIN (for local development)
# ============================================================================

if __name__ == "__main__":
    logger.info("🔧 Starting LangChain agent in development mode...")
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,  # Auto-reload on code changes
        log_level="info"
    )
