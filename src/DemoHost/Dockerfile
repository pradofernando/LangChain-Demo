# ============================================================================
# Dockerfile - .NET Host
# ============================================================================
# Builds the ASP.NET Core minimal API that wraps the LangChain agent.
#
# Build:
#   docker build -t support-agent-host:latest -f src/DemoHost/Dockerfile .
#
# Run:
#   docker run -p 8080:8080 -e LangChainAgent__BaseUrl=http://host.docker.internal:8000 support-agent-host:latest
#
# ============================================================================

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project file and restore dependencies
COPY src/DemoHost/DemoHost.csproj src/DemoHost/
RUN dotnet restore src/DemoHost/DemoHost.csproj

# Copy source code and build
COPY src/DemoHost/ src/DemoHost/
RUN dotnet build src/DemoHost/DemoHost.csproj -c Release -o /app/build

# Publish
FROM build AS publish
RUN dotnet publish src/DemoHost/DemoHost.csproj -c Release -o /app/publish /p:UseAppHost=false

# Final runtime image
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy published app
COPY --from=publish /app/publish .

# Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Set environment
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Start application
ENTRYPOINT ["dotnet", "DemoHost.dll"]
