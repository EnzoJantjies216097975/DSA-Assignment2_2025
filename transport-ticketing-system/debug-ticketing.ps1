# Save as debug-ticketing.ps1

Write-Host "TICKETING SERVICE DEBUG" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor Cyan
Write-Host ""

# 1. Check ticketing service status and logs
Write-Host "1. Ticketing Service Status" -ForegroundColor Yellow
$ticketingStatus = docker-compose ps ticketing-service --format json | ConvertFrom-Json
Write-Host "   Status: $($ticketingStatus.Status)" -ForegroundColor $(if($ticketingStatus.Status -like "*Up*"){"Green"}else{"Red"})

# 2. Check ticketing service logs
Write-Host "`n2. Ticketing Service Logs" -ForegroundColor Yellow
$ticketingLogs = docker-compose logs ticketing-service --tail=20
$ticketingLogs | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }

# 3. Check for errors in logs
Write-Host "`n3. Error Analysis" -ForegroundColor Yellow
$errorLogs = docker-compose logs ticketing-service 2>$null | Select-String -Pattern "error|exception|fail|closed|payment" -CaseSensitive:$false
if ($errorLogs) {
    Write-Host "   Found errors:" -ForegroundColor Red
    $errorLogs | Select-Object -First 10 | ForEach-Object { Write-Host "   - $($_.Line)" -ForegroundColor Red }
} else {
    Write-Host "   No obvious errors in logs" -ForegroundColor Green
}

# 4. Test ticketing service health endpoint (using port 9096)
Write-Host "`n4. Testing Ticketing Service Health" -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/health" -Method Get -TimeoutSec 5
    Write-Host "   [OK] Health: $health" -ForegroundColor Green
} catch {
    Write-Host "   [ERROR] Health check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Test ticketing service endpoints (using port 9096)
Write-Host "`n5. Testing Ticketing Endpoints" -ForegroundColor Yellow

# Test getting user tickets (correct endpoint)
try {
    $tickets = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/users/test-user-123/tickets" -Method Get -TimeoutSec 5
    Write-Host "   [OK] Can list user tickets" -ForegroundColor Green
    Write-Host "   Found $($tickets.Count) tickets" -ForegroundColor Gray
} catch {
    Write-Host "   [WARN] Cannot list user tickets: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 6. Check service connectivity within Docker network
Write-Host "`n6. Testing Internal Service Connectivity" -ForegroundColor Yellow

# Test from within ticketing-service container (internal port 9092)
Write-Host "   Testing payment service from ticketing container..." -ForegroundColor Gray
$paymentHealth = docker-compose exec ticketing-service curl -s http://payment-service:9093/payment/health
if ($LASTEXITCODE -eq 0) {
    Write-Host "   [OK] ticketing-service can reach payment-service internally" -ForegroundColor Green
    Write-Host "   Payment service response: $paymentHealth" -ForegroundColor Gray
} else {
    Write-Host "   [ERROR] Internal connectivity failed" -ForegroundColor Red
}

# 7. Test payment service directly (from host - port 9093)
Write-Host "`n7. Testing Payment Service from Host" -ForegroundColor Yellow
try {
    $paymentHealth = Invoke-RestMethod -Uri "http://localhost:9093/payment/health" -Method Get -TimeoutSec 5
    Write-Host "   [OK] Payment Service Health: $paymentHealth" -ForegroundColor Green
} catch {
    Write-Host "   [ERROR] Cannot reach payment service: $($_.Exception.Message)" -ForegroundColor Red
}

# 8. Test complete ticket purchase flow (using port 9096)
Write-Host "`n8. Testing Complete Ticket Purchase Flow" -ForegroundColor Yellow
try {
    $purchaseBody = @{
        userId = "test-user-123"
        ticketType = "SINGLE_RIDE"
        paymentMethod = "CREDIT_CARD"
    } | ConvertTo-Json
    
    Write-Host "   Purchasing ticket..." -ForegroundColor Gray
    $purchaseResult = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/tickets/purchase" `
        -Method Post `
        -ContentType "application/json" `
        -Body $purchaseBody `
        -TimeoutSec 10
    
    Write-Host "   [SUCCESS] Ticket purchase initiated!" -ForegroundColor Green
    Write-Host "   Ticket ID: $($purchaseResult.ticketId)" -ForegroundColor Gray
    Write-Host "   Status: $($purchaseResult.status)" -ForegroundColor Gray
    Write-Host "   Price: $($purchaseResult.price)" -ForegroundColor Gray
    
    # Wait a bit for async processing
    Write-Host "   Waiting for payment processing..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    # Check ticket status
    Write-Host "   Checking final ticket status..." -ForegroundColor Gray
    $ticketStatus = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/tickets/$($purchaseResult.ticketId)" -Method Get -TimeoutSec 5
    Write-Host "   Final Ticket Status: $($ticketStatus.status)" -ForegroundColor $(if($ticketStatus.status -eq "PAID"){"Green"}else{"Yellow"})
    
    if ($ticketStatus.status -eq "PAID") {
        Write-Host "   [SUCCESS] Payment processed automatically via Kafka!" -ForegroundColor Green
    } else {
        Write-Host "   [INFO] Ticket status: $($ticketStatus.status)" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "   [ERROR] Ticket purchase failed: $($_.Exception.Message)" -ForegroundColor Red
}

# 9. Check Kafka topics and messages
Write-Host "`n9. Checking Kafka Status" -ForegroundColor Yellow
try {
    Write-Host "   Listing Kafka topics..." -ForegroundColor Gray
    $kafkaStatus = docker-compose exec kafka kafka-topics.sh --list --bootstrap-server localhost:9092
    Write-Host "   Kafka Topics:" -ForegroundColor Gray
    $kafkaStatus | ForEach-Object { Write-Host "   - $_" -ForegroundColor Gray }
    
    # Check messages in ticket.requests topic
    Write-Host "   Checking ticket.requests topic..." -ForegroundColor Gray
    $ticketRequests = docker-compose exec kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic ticket.requests --from-beginning --max-messages 3 --timeout-ms 5000 2>&1
    if ($ticketRequests -and $ticketRequests -notlike "*Processed a total of 0 messages*") {
        Write-Host "   [OK] Messages found in ticket.requests topic" -ForegroundColor Green
    } else {
        Write-Host "   [INFO] No messages in ticket.requests topic" -ForegroundColor Yellow
    }
    
    # Check messages in payments.processed topic
    Write-Host "   Checking payments.processed topic..." -ForegroundColor Gray
    $paymentProcessed = docker-compose exec kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments.processed --from-beginning --max-messages 3 --timeout-ms 5000 2>&1
    if ($paymentProcessed -and $paymentProcessed -notlike "*Processed a total of 0 messages*") {
        Write-Host "   [OK] Messages found in payments.processed topic" -ForegroundColor Green
    } else {
        Write-Host "   [INFO] No messages in payments.processed topic" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "   [WARN] Could not check Kafka topics: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 10. Check if services are communicating properly
Write-Host "`n10. Service Communication Check" -ForegroundColor Yellow
Write-Host "   Ticketing Service: http://localhost:9096" -ForegroundColor Gray
Write-Host "   Payment Service: http://localhost:9093" -ForegroundColor Gray
Write-Host "   Kafka: localhost:29092" -ForegroundColor Gray
Write-Host "   MongoDB: localhost:27017" -ForegroundColor Gray

Write-Host "`n=======================" -ForegroundColor Cyan
Write-Host "DEBUG COMPLETE" -ForegroundColor Cyan