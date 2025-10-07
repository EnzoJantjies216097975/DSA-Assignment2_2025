# Save as debug-payment.ps1

Write-Host "PAYMENT SERVICE DEBUG" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan
Write-Host ""

# 1. Check payment service status
Write-Host "1. Payment Service Status" -ForegroundColor Yellow
$paymentStatus = docker-compose ps payment-service --format json | ConvertFrom-Json
Write-Host "   Status: $($paymentStatus.Status)" -ForegroundColor $(if($paymentStatus.Status -like "*Up*"){"Green"}else{"Red"})

# 2. Check payment service logs
Write-Host "`n2. Payment Service Logs" -ForegroundColor Yellow
$paymentLogs = docker-compose logs payment-service --tail=15
$paymentLogs | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }

# 3. Check for errors in logs
Write-Host "`n3. Error Analysis" -ForegroundColor Yellow
$errorLogs = docker-compose logs payment-service 2>$null | Select-String -Pattern "error|exception|fail|closed" -CaseSensitive:$false
if ($errorLogs) {
    Write-Host "   Found errors:" -ForegroundColor Red
    $errorLogs | Select-Object -First 5 | ForEach-Object { Write-Host "   - $($_.Line)" -ForegroundColor Red }
} else {
    Write-Host "   No obvious errors in logs" -ForegroundColor Green
}

# 4. Test payment service health endpoint
Write-Host "`n4. Testing Payment Service Health" -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost:9093/payment/health" -Method Get -TimeoutSec 5
    Write-Host "   [OK] Health: $health" -ForegroundColor Green
} catch {
    Write-Host "   [ERROR] Health check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Check Kafka connectivity
Write-Host "`n5. Kafka Status" -ForegroundColor Yellow
$kafkaStatus = docker-compose ps kafka --format json | ConvertFrom-Json
Write-Host "   Kafka Status: $($kafkaStatus.Status)" -ForegroundColor $(if($kafkaStatus.Status -like "*Up*"){"Green"}else{"Red"})

# 6. Test manual payment processing
Write-Host "`n6. Testing Manual Payment" -ForegroundColor Yellow
try {
    $testPayment = @{
        ticketId = "test-ticket-123"
        userId = "test-user-123" 
        amount = 15.00
        paymentMethod = "CREDIT_CARD"
    } | ConvertTo-Json
    
    $payment = Invoke-RestMethod -Uri "http://localhost:9093/payment/payments/process" `
        -Method Post `
        -ContentType "application/json" `
        -Body $testPayment `
        -TimeoutSec 10
    
    Write-Host "   [SUCCESS] Manual payment processed!" -ForegroundColor Green
    Write-Host "   Payment ID: $($payment.paymentId)" -ForegroundColor Gray
    Write-Host "   Status: $($payment.status)" -ForegroundColor Gray
    
} catch {
    Write-Host "   [ERROR] Manual payment failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=====================" -ForegroundColor Cyan
Write-Host "DEBUG COMPLETE" -ForegroundColor Cyan