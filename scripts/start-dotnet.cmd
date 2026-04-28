@echo off
cd /d "%~dp0..\src\DemoHost"
set ASPNETCORE_URLS=http://localhost:8080
dotnet run --no-build
