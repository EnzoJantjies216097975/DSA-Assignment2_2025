# Save as debug-comprehensive.ps1

Write-Host "COMPREHENSIVE TRANSPORT SYSTEM DEBUG" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check all services status
Write-Host "1. SERVICE STATUS CHECK" -ForegroundColor Yellow
$services = @(
    "passenger-service",
    "transport-service", 
    "ticketing-service",
    "payment-service",
    "admin-service",
    "notification-service",
    "mongodb",
    "kafka",
    "zookeeper"
)

foreach ($service in $services) {
    $status = docker-compose ps $service --format json | ConvertFrom-Json 2>$null
    if ($status) {
        $color = if ($status.Status -like "*Up*") { "Green" } else { "Red" }
        Write-Host "   $($service.PadRight(20)): $($status.Status)" -ForegroundColor $color
    } else {
        Write-Host "   $($service.PadRight(20)): NOT FOUND" -ForegroundColor Red
    }
}

# 2. Check MongoDB connectivity and data
Write-Host "`n2. MONGODB CHECK" -ForegroundColor Yellow
try {
    # Test basic connection
    $mongoTest = docker exec -i mongodb mongosh -u admin -p password123 --quiet --eval "db.adminCommand('ismaster')" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   [OK] MongoDB connection successful" -ForegroundColor Green
        
        # Check if transport_db exists and has collections
        $collections = docker exec -i mongodb mongosh -u admin -p password123 --quiet --eval "
            use transport_db;
            db.getCollectionNames();
        " 2>&1
        Write-Host "   Collections: $collections" -ForegroundColor Gray
        
        # Count users
        $userCount = docker exec -i mongodb mongosh -u admin -p password123 --quiet --eval "
            use transport_db;
            db.users.countDocuments();
        " 2>&1
        Write-Host "   Total users: $userCount" -ForegroundColor Gray
    }
} catch {
    Write-Host "   [ERROR] MongoDB check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. Check service logs for errors
Write-Host "`n3. SERVICE LOGS CHECK" -ForegroundColor Yellow
$criticalServices = @("passenger-service", "payment-service")

foreach ($service in $criticalServices) {
    Write-Host "   $service logs:" -ForegroundColor Gray
    try {
        $logs = docker-compose logs $service --tail=5 2>$null
        if ($logs) {
            $logs | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
        } else {
            Write-Host "      No logs available" -ForegroundColor Yellow
        }
        
        # Check for specific errors
        $errorLogs = docker-compose logs $service 2>$null | Select-String -Pattern "error|exception|fail" -CaseSensitive:$false
        if ($errorLogs) {
            Write-Host "   [ERRORS FOUND]:" -ForegroundColor Red
            $errorLogs | Select-Object -First 3 | ForEach-Object { Write-Host "      $($_.Line)" -ForegroundColor Red }
        }
    } catch {
        Write-Host "      Could not retrieve logs" -ForegroundColor Yellow
    }
    Write-Host ""
}

# 4. Test passenger service endpoints directly
Write-Host "4. DIRECT ENDPOINT TESTING" -ForegroundColor Yellow

# Test health endpoint
Write-Host "   Testing health endpoint..." -ForegroundColor Gray
try {
    $health = Invoke-RestMethod -Uri "http://localhost:9090/passenger/health" -Method Get -TimeoutSec 5
    Write-Host "   [OK] Health: $health" -ForegroundColor Green
} catch {
    Write-Host "   [ERROR] Health check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test registration with detailed error handling
Write-Host "   Testing registration endpoint..." -ForegroundColor Gray
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$testEmail = "test$timestamp@demo.com"

$registerBody = @{
    email = $testEmail
    password = "test123"
    firstName = "Test"
    lastName = "User"
    phone = "+264811111111"
} | ConvertTo-Json

try {
    $response = Invoke-WebRequest -Uri "http://localhost:9090/passenger/register" `
        -Method Post `
        -ContentType "application/json" `
        -Body $registerBody `
        -TimeoutSec 10
    
    Write-Host "   [SUCCESS] Registration worked!" -ForegroundColor Green
    Write-Host "   Status: $($response.StatusCode)" -ForegroundColor Gray
    Write-Host "   Response: $($response.Content)" -ForegroundColor Gray
    
} catch {
    Write-Host "   [ERROR] Registration failed" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "   HTTP Status: $statusCode" -ForegroundColor Red
        
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $errorBody = $reader.ReadToEnd()
            Write-Host "   Error Body: $errorBody" -ForegroundColor Yellow
        } catch {
            Write-Host "   Could not read error response" -ForegroundColor Gray
        }
    }
    Write-Host "   Exception: $($_.Exception.Message)" -ForegroundColor Gray
}

# 5. Test network connectivity between containers
Write-Host "`n5. NETWORK CONNECTIVITY" -ForegroundColor Yellow
Write-Host "   Testing if passenger-service can reach MongoDB..." -ForegroundColor Gray
try {
    $networkTest = docker-compose exec passenger-service ping -c 2 mongodb 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   [OK] passenger-service can reach mongodb" -ForegroundColor Green
    } else {
        Write-Host "   [ERROR] Network connectivity issue" -ForegroundColor Red
    }
} catch {
    Write-Host "   [ERROR] Network test failed" -ForegroundColor Red
}

Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "DEBUG COMPLETE" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan