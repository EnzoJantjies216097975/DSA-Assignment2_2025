# Test in separate window
Write-Host "TESTING AUTOMATIC PAYMENT PROCESSING" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Wait for service to start
Start-Sleep -Seconds 8

# Test 1: Manual payment (to verify service works)
Write-Host "`n1. Testing manual payment (verification):" -ForegroundColor Yellow
$manualBody = @{
    ticketId = "test-manual-001"
    userId = "test-user-manual"
    amount = 15.00
    paymentMethod = "CREDIT_CARD"
} | ConvertTo-Json

try {
    $manualResult = Invoke-RestMethod -Uri "http://localhost:9093/payment/payments/process" -Method Post -ContentType "application/json" -Body $manualBody
    Write-Host "   Manual payment: $($manualResult.message)" -ForegroundColor Green
} catch {
    Write-Host "   Manual payment failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Automatic payment via ticket purchase
Write-Host "`n2. Testing automatic payment via ticket purchase:" -ForegroundColor Yellow
$purchaseBody = @{
    userId = "test-kafka-final-" + (Get-Date -Format "HHmmss")
    ticketType = "SINGLE_RIDE"
    paymentMethod = "CREDIT_CARD"
} | ConvertTo-Json

try {
    $purchaseResult = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/tickets/purchase" -Method Post -ContentType "application/json" -Body $purchaseBody
    Write-Host "   Ticket created: $($purchaseResult.ticketId)" -ForegroundColor Green
    Write-Host "   Initial status: $($purchaseResult.status)" -ForegroundColor Gray
    
    # Wait for processing
    Write-Host "   Waiting 15 seconds for automatic payment..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    
    # Check final status
    $finalStatus = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/tickets/$($purchaseResult.ticketId)" -Method Get
    Write-Host "   Final status: $($finalStatus.status)" -ForegroundColor $(if($finalStatus.status -eq "PAID"){"Green"}else{"Red"})
    
} catch {
    Write-Host "   Ticket purchase failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Check Kafka topics
Write-Host "`n3. Checking Kafka topics:" -ForegroundColor Yellow
docker-compose exec kafka /bin/bash -c "/usr/bin/kafka-topics --list --bootstrap-server localhost:9092"

Write-Host "`n4. Checking consumer groups:" -ForegroundColor Yellow
docker-compose exec kafka /bin/bash -c "/usr/bin/kafka-consumer-groups --list --bootstrap-server localhost:9092"