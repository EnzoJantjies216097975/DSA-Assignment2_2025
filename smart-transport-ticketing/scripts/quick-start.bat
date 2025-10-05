@echo off
REM Simple Batch File for Quick Project Startup
REM Save as: quick-start.bat
REM Run by double-clicking or typing: quick-start.bat

echo =============================================
echo Smart Transport Ticketing System
echo Quick Start for Windows
echo =============================================
echo.

REM Check if Docker is running
docker version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Docker is not running!
    echo Please start Docker Desktop and try again.
    pause
    exit /b 1
)

echo Docker is running...
echo.

REM Ask about cleanup
set /p cleanup="Clean up existing containers? (y/n): "
if /i "%cleanup%"=="y" (
    echo Cleaning up...
    docker-compose down -v
)

echo.
echo Starting services...
echo This will take several minutes on first run...
echo.

REM Start all services
docker-compose up -d --build

if %errorlevel% neq 0 (
    echo.
    echo ERROR: Failed to start services!
    echo Check docker-compose.yml and service configurations.
    pause
    exit /b 1
)

echo.
echo Waiting 30 seconds for services to initialize...
timeout /t 30 /nobreak >nul

echo.
echo =============================================
echo Services should now be running!
echo =============================================
echo.
echo Check these URLs:
echo   - Kafka UI: http://localhost:8090
echo   - Passenger Service: http://localhost:8081
echo   - Transport Service: http://localhost:8082
echo   - Admin Panel: http://localhost:9090
echo.
echo Useful commands:
echo   - View logs: docker logs -f [service-name]
echo   - Stop all: docker-compose down
echo   - Check status: docker ps
echo.
echo To run tests, use: test-basic.bat
echo.
pause