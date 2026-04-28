# ============================================================================
# Dockerfile - LangChain Agent
# ============================================================================
# Builds the Python FastAPI service that hosts the LangChain ReAct agent.
#
# Build:
#   docker build -t langchain-agent:latest -f src/LangChainAgent/Dockerfile .
#
# Run:
#   docker run -p 8000:8000 -e OPENAI_API_KEY=your-key langchain-agent:latest
#
# ============================================================================

FROM python:3.11-slim AS base
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY src/LangChainAgent/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/LangChainAgent/ .

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser
RUN chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8000

# Environment variables
ENV PYTHONUNBUFFERED=1
ENV LOG_LEVEL=INFO

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# Start application
CMD ["python", "main.py"]
