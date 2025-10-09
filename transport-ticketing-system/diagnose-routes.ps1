# Diagnose Routes Issue
# Save as: diagnose-routes.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSE ROUTES ISSUE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Test transport service health
Write-Host "Step 1: Testing transport service..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost:9091/transport/health" -Method Get -TimeoutSec 5
    Write-Host "[OK] Transport service is running: $health" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Transport service is not responding!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

Write-Host ""

# Step 2: Check what's in MongoDB
Write-Host "Step 2: Checking routes in MongoDB..." -ForegroundColor Yellow
$mongoContainer = docker ps --format "{{.Names}}" | Select-String -Pattern "mongodb" | Select-Object -First 1

if ($mongoContainer) {
    $mongoContainer = $mongoContainer.ToString()
    Write-Host "[OK] Found MongoDB: $mongoContainer" -ForegroundColor Green
    
    # Count routes
    $mongoCommand = 'use transport_db; db.routes.countDocuments()'
    $count = docker exec -i $mongoContainer mongosh -u admin -p password123 --quiet --eval $mongoCommand 2>&1
    Write-Host "Routes in database: $count" -ForegroundColor Cyan
    
    # Show routes
    $mongoCommand = 'use transport_db; db.routes.find().limit(5)'
    $routes = docker exec -i $mongoContainer mongosh -u admin -p password123 --quiet --eval $mongoCommand 2>&1
    Write-Host ""
    Write-Host "Sample routes:" -ForegroundColor Cyan
    Write-Host $routes
} else {
    Write-Host "[ERROR] MongoDB container not found" -ForegroundColor Red
}

Write-Host ""

# Step 3: Test the API endpoint directly
Write-Host "Step 3: Testing /transport/routes endpoint..." -ForegroundColor Yellow
try {
    $routes = Invoke-RestMethod -Uri "http://localhost:9091/transport/routes" -Method Get -TimeoutSec 10
    Write-Host "[SUCCESS] Routes fetched successfully!" -ForegroundColor Green
    Write-Host "Number of routes: $($routes.Count)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Routes:" -ForegroundColor Cyan
    $routes | ConvertTo-Json -Depth 10
} catch {
    Write-Host "[ERROR] Failed to fetch routes from API" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error Details:" -ForegroundColor Yellow
    Write-Host "Status Code: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    Write-Host "Status Description: $($_.Exception.Response.StatusDescription)" -ForegroundColor Red
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor Red
    
    # Try to get response body
    try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host ""
        Write-Host "Response Body:" -ForegroundColor Yellow
        Write-Host $responseBody -ForegroundColor Red
    } catch {
        Write-Host "Could not read response body" -ForegroundColor Gray
    }
}

Write-Host ""

# Step 4: Check transport service logs
Write-Host "Step 4: Checking transport service logs..." -ForegroundColor Yellow
Write-Host ""
Write-Host "Last 30 lines of logs:" -ForegroundColor Cyan
docker-compose logs transport-service --tail=30

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Check the logs above for errors" -ForegroundColor White
Write-Host "2. If you see compilation errors, rebuild: docker-compose up -d --build transport-service" -ForegroundColor White
Write-Host "3. If MongoDB query fails, the service code needs updating" -ForegroundColor White
Write-Host ""

Read-Host "Press Enter to exit"