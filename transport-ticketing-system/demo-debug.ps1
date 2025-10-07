# Save this as demo-debug.ps1

Write-Host "Transport Ticketing System - DEBUG MODE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Test MongoDB connection with correct container name
Write-Host "1. Testing MongoDB connection..." -ForegroundColor Yellow
try {
    $mongoTest = docker exec -i mongodb mongosh -u admin -p password123 --quiet --eval "db.adminCommand('ismaster')" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   [OK] MongoDB is running and accessible" -ForegroundColor Green
    } else {
        Write-Host "   [ERROR] MongoDB connection failed" -ForegroundColor Red
        Write-Host "   Output: $mongoTest" -ForegroundColor Gray
        exit
    }
} catch {
    Write-Host "   [ERROR] MongoDB test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# 2. Check database structure
Write-Host "`n2. Checking database structure..." -ForegroundColor Yellow
try {
    $collections = docker exec -i mongodb mongosh -u admin -p password123 --quiet --eval "
        use transport_db;
        db.getCollectionNames();
    " 2>&1
    Write-Host "   Collections in transport_db: $collections" -ForegroundColor Gray
} catch {
    Write-Host "   [ERROR] Database check failed" -ForegroundColor Red
}

# 3. Check passenger service logs for MongoDB connection errors
Write-Host "`n3. Checking passenger service logs..." -ForegroundColor Yellow
try {
    $logs = docker-compose logs passenger-service --tail=10
    Write-Host "   Last 10 lines of passenger-service logs:" -ForegroundColor Gray
    $logs | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
} catch {
    Write-Host "   [ERROR] Could not get logs" -ForegroundColor Red
}

# 4. Check payment service issue (it's restarting)
Write-Host "`n4. Checking payment service status..." -ForegroundColor Yellow
Write-Host "   [WARNING] Payment service is restarting - this might affect ticket purchases" -ForegroundColor Yellow
try {
    $paymentLogs = docker-compose logs payment-service --tail=5
    Write-Host "   Payment service logs:" -ForegroundColor Gray
    $paymentLogs | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
} catch {
    Write-Host "   Could not get payment service logs" -ForegroundColor Gray
}

# 5. Test registration endpoint
Write-Host "`n5. Testing registration endpoint..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$email = "test$timestamp@demo.com"

$registerBody = @{
    email = $email
    password = "test123"
    firstName = "Test"
    lastName = "User"
    phone = "+264811111111"
} | ConvertTo-Json

Write-Host "   Using email: $email" -ForegroundColor Gray

try {
    $response = Invoke-RestMethod -Uri "http://localhost:9090/passenger/register" `
        -Method Post `
        -ContentType "application/json" `
        -Body $registerBody `
        -TimeoutSec 10
    
    Write-Host "   [SUCCESS] Registration worked!" -ForegroundColor Green
    Write-Host "   User ID: $($response.userId)" -ForegroundColor Gray
    Write-Host "   Message: $($response.message)" -ForegroundColor Gray
    
} catch {
    Write-Host "   [ERROR] Registration failed: $($_.Exception.Message)" -ForegroundColor Red
    
    # Get more detailed error information
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "   HTTP Status Code: $statusCode" -ForegroundColor Red
        
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $errorBody = $reader.ReadToEnd()
            Write-Host "   Error Response: $errorBody" -ForegroundColor Yellow
        } catch {
            Write-Host "   Could not read error response body" -ForegroundColor Gray
        }
    }
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "DEBUG COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan