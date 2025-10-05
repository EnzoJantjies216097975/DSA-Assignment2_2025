# Smart Transport Ticketing System - Windows Startup Script
# Run this from PowerShell in the smart-transport-ticketing directory
# To run: .\startup.ps1

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Smart Transport Ticketing System" -ForegroundColor Cyan
Write-Host "DSA Assignment 2 - Group Project" -ForegroundColor Cyan
Write-Host "Windows Environment Setup" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Function to check if a command exists
function Test-Command {
    param($Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Function to create a directory if it doesn't exist
function Ensure-Directory {
    param($Path)
    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "Created directory: $Path" -ForegroundColor Green
    }
}

# Function to create a file with content if it doesn't exist
function Ensure-File {
    param($Path, $Content)
    if (!(Test-Path $Path)) {
        Set-Content -Path $Path -Value $Content
        Write-Host "Created file: $Path" -ForegroundColor Green
    }
}

# Step 1: Check prerequisites
Write-Host "Step 1: Checking prerequisites..." -ForegroundColor Yellow

if (!(Test-Command "docker")) {
    Write-Host "❌ Docker is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    exit 1
}

# Check if Docker is running
try {
    docker info | Out-Null
    Write-Host "✅ Docker is installed and running" -ForegroundColor Green
}
catch {
    Write-Host "❌ Docker is installed but not running" -ForegroundColor Red
    Write-Host "Please start Docker Desktop and try again" -ForegroundColor Yellow
    exit 1
}

# Check Docker Compose (it's included with Docker Desktop on Windows)
$dockerComposeV2 = $false
try {
    docker compose version | Out-Null
    $dockerComposeV2 = $true
    Write-Host "✅ Docker Compose V2 detected" -ForegroundColor Green
}
catch {
    if (Test-Command "docker-compose") {
        Write-Host "✅ Docker Compose V1 detected" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Docker Compose is not available" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# Step 2: Optional cleanup
Write-Host "Step 2: Cleanup option..." -ForegroundColor Yellow
$cleanup = Read-Host "Do you want to clean up existing containers and volumes? (y/n)"

if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
    Write-Host "Cleaning up existing containers..." -ForegroundColor Cyan
    if ($dockerComposeV2) {
        docker compose down -v
    }
    else {
        docker-compose down -v
    }
    Write-Host "✅ Cleanup complete" -ForegroundColor Green
}

Write-Host ""

# Step 3: Create necessary directories
Write-Host "Step 3: Creating necessary directories..." -ForegroundColor Yellow

# Create infrastructure directories
Ensure-Directory "infrastructure\kafka"
Ensure-Directory "infrastructure\nginx"
Ensure-Directory "infrastructure\mongodb"
Ensure-Directory "docker"

# Create service directories if missing
$services = @(
    "passenger-service",
    "transport-service",
    "ticketing-service",
    "payment-service",
    "notification-service",
    "admin-service",
    "validation-service",
    "cli-client"
)

foreach ($service in $services) {
    Ensure-Directory "services\$service"
}

Write-Host "✅ Directory structure verified" -ForegroundColor Green
Write-Host ""

# Step 4: Ensure all services have required files
Write-Host "Step 4: Verifying service files..." -ForegroundColor Yellow

$dependenciesToml = @"
[[dependency]]
org = "ballerinax"
name = "mongodb"
version = "5.0.0"

[[dependency]]
org = "ballerinax"
name = "kafka"
version = "4.0.0"

[[dependency]]
org = "ballerina"
name = "http"
version = "2.11.0"

[[dependency]]
org = "ballerina"
name = "log"
version = "2.10.0"

[[dependency]]
org = "ballerina"
name = "time"
version = "2.5.0"

[[dependency]]
org = "ballerina"
name = "uuid"
version = "1.8.0"

[[dependency]]
org = "ballerina"
name = "crypto"
version = "2.7.0"

[[dependency]]
org = "ballerina"
name = "jwt"
version = "2.13.0"
"@

$configToml = @"
[ballerina]
[ballerina.log]
level = "INFO"

[service]
host = "0.0.0.0"
"@

# Skip cli-client as it's not a service
$serviceList = $services | Where-Object { $_ -ne "cli-client" }

foreach ($service in $serviceList) {
    $servicePath = "services\$service"
    
    # Ensure Dependencies.toml exists
    Ensure-File "$servicePath\Dependencies.toml" $dependenciesToml
    
    # Ensure Config.toml exists
    Ensure-File "$servicePath\Config.toml" $configToml
    
    # Check if main.bal exists (we won't create it if missing)
    if (!(Test-Path "$servicePath\main.bal") -and !(Test-Path "$servicePath\service.bal")) {
        Write-Host "⚠️  Warning: No main.bal or service.bal found in $service" -ForegroundColor Yellow
    }
}

Write-Host "✅ Service files verified" -ForegroundColor Green
Write-Host ""

# Step 5: Check and fix critical configuration files
Write-Host "Step 5: Verifying configuration files..." -ForegroundColor Yellow

# Check if .env exists
if (!(Test-Path ".env")) {
    Write-Host "Creating .env file..." -ForegroundColor Cyan
    $envContent = @"
# MongoDB Configuration
MONGO_HOST=mongodb
MONGO_PORT=27017
MONGO_DATABASE=transport_db

# Kafka Configuration
KAFKA_BOOTSTRAP_SERVERS=kafka:9092

# JWT Configuration
JWT_SECRET=your-secret-key-change-in-production-2025
JWT_ISSUER=smart-transport-system

# Email Configuration (for notifications)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=noreply@transport.windhoek.com
SMTP_PASSWORD=your-app-specific-password
"@
    Set-Content -Path ".env" -Value $envContent
    Write-Host "✅ .env file created" -ForegroundColor Green
}

Write-Host "✅ Configuration files ready" -ForegroundColor Green
Write-Host ""

# Step 6: Build and start services
Write-Host "Step 6: Building and starting services..." -ForegroundColor Yellow
Write-Host "This may take several minutes on first run..." -ForegroundColor Cyan

try {
    if ($dockerComposeV2) {
        docker compose up -d --build
    }
    else {
        docker-compose up -d --build
    }
    Write-Host "✅ Docker Compose started successfully" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to start services" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Waiting for services to initialize (30 seconds)..." -ForegroundColor Cyan
Start-Sleep -Seconds 30

# Step 7: Check service health
Write-Host ""
Write-Host "Step 7: Checking service health..." -ForegroundColor Yellow

$services = @(
    @{Name = "mongodb"; Port = 27017 },
    @{Name = "kafka"; Port = 9092 },
    @{Name = "zookeeper"; Port = 2181 },
    @{Name = "passenger-service"; Port = 8081 },
    @{Name = "transport-service"; Port = 8082 },
    @{Name = "ticketing-service"; Port = 8083 },
    @{Name = "payment-service"; Port = 8084 },
    @{Name = "notification-service"; Port = 8085 },
    @{Name = "admin-service"; Port = 9090 },
    @{Name = "kafka-ui"; Port = 8090 }
)

$allHealthy = $true
foreach ($service in $services) {
    $containerName = $service.Name
    $port = $service.Port
    
    try {
        $status = docker inspect $containerName --format '{{.State.Status}}' 2>$null
        if ($status -eq "running") {
            Write-Host ("✅ {0} is running on port {1}" -f $containerName, $port) -ForegroundColor Green
        }
        else {
            Write-Host ("❌ {0} is not running (status: {1})" -f $containerName, $status) -ForegroundColor Red
            $allHealthy = $false
        }
    }
    catch {
        Write-Host ("⚠️  {0} container not found" -f $containerName) -ForegroundColor Yellow
        $allHealthy = $false
    }
}

Write-Host ""

# Step 8: Test MongoDB collections
Write-Host "Step 8: Verifying MongoDB setup..." -ForegroundColor Yellow
try {
    $collections = docker exec mongodb mongosh --quiet transport_db --eval "db.getCollectionNames().join(',')" 2>$null
    if ($collections -match "users") {
        Write-Host "✅ MongoDB collections created successfully" -ForegroundColor Green
        Write-Host "Collections: $collections" -ForegroundColor Cyan
    }
    else {
        Write-Host "⚠️  MongoDB collections may not be properly initialized" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "⚠️  Could not verify MongoDB collections" -ForegroundColor Yellow
}

Write-Host ""

# Step 9: Test Kafka topics
Write-Host "Step 9: Verifying Kafka topics..." -ForegroundColor Yellow
try {
    $topics = docker exec kafka kafka-topics.sh --list --bootstrap-server localhost:9092 2>$null
    if ($topics -match "ticket.requests") {
        Write-Host "✅ Kafka topics created successfully" -ForegroundColor Green
        Write-Host "Topics found: $($topics -replace "`n", ", ")" -ForegroundColor Cyan
    }
    else {
        Write-Host "⚠️  Kafka topics may not be properly created" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "⚠️  Could not verify Kafka topics" -ForegroundColor Yellow
}

Write-Host ""

# Final summary
Write-Host "=============================================" -ForegroundColor Cyan
if ($allHealthy) {
    Write-Host "✅ All services are running successfully!" -ForegroundColor Green
}
else {
    Write-Host "⚠️  Some services may not be running correctly" -ForegroundColor Yellow
    Write-Host "Check logs with: docker logs [container-name]" -ForegroundColor Yellow
}
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Access points:" -ForegroundColor Green
Write-Host "  • Kafka UI: http://localhost:8090" -ForegroundColor White
Write-Host "  • API Gateway: http://localhost:80" -ForegroundColor White
Write-Host "  • MongoDB: localhost:27017" -ForegroundColor White
Write-Host ""
Write-Host "Service endpoints:" -ForegroundColor Green
Write-Host "  • Passenger Service: http://localhost:8081" -ForegroundColor White
Write-Host "  • Transport Service: http://localhost:8082" -ForegroundColor White
Write-Host "  • Ticketing Service: http://localhost:8083" -ForegroundColor White
Write-Host "  • Payment Service: http://localhost:8084" -ForegroundColor White
Write-Host "  • Notification Service: http://localhost:8085" -ForegroundColor White
Write-Host "  • Admin Service: http://localhost:9090" -ForegroundColor White
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Green
Write-Host "  • View logs: docker logs -f [service-name]" -ForegroundColor White
Write-Host "  • Stop all: docker compose down" -ForegroundColor White
Write-Host "  • Restart service: docker compose restart [service-name]" -ForegroundColor White
Write-Host "  • Run CLI client: docker exec -it cli-client bal run" -ForegroundColor White
Write-Host ""
Write-Host "To run tests, execute: .\test-system.ps1" -ForegroundColor Yellow
Write-Host ""