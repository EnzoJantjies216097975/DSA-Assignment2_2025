Write-Host "Testing Kafka Connectivity" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

# Test if Kafka is reachable from payment service
Write-Host "`n1. Testing Kafka connectivity from payment service" -ForegroundColor Yellow
docker-compose exec payment-service /bin/bash -c "nc -zv kafka 9092 && echo 'Kafka connection successful' || echo 'Kafka connection failed'"

# Test if Kafka is reachable from ticketing service  
Write-Host "`n2. Testing Kafka connectivity from ticketing service" -ForegroundColor Yellow
docker-compose exec ticketing-service /bin/bash -c "nc -zv kafka 9092 && echo 'Kafka connection successful' || echo 'Kafka connection failed'"

# List topics using docker exec with full path
Write-Host "`n3. Checking Kafka Topics" -ForegroundColor Yellow
try {
    $topics = docker-compose exec kafka /bin/bash -c "/usr/bin/kafka-topics --list --bootstrap-server localhost:9092"
    if ($topics) {
        Write-Host "   Found topics:" -ForegroundColor Green
        $topics | ForEach-Object { Write-Host "   - $_" -ForegroundColor Gray }
    } else {
        Write-Host "   No topics found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   [ERROR] Could not list topics: $($_.Exception.Message)" -ForegroundColor Red
}

# Check consumer groups
Write-Host "`n4. Checking Consumer Groups" -ForegroundColor Yellow
try {
    $groups = docker-compose exec kafka /bin/bash -c "/usr/bin/kafka-consumer-groups --list --bootstrap-server localhost:9092"
    if ($groups) {
        Write-Host "   Found consumer groups:" -ForegroundColor Green
        $groups | ForEach-Object { Write-Host "   - $_" -ForegroundColor Gray }
    } else {
        Write-Host "   No consumer groups found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   [ERROR] Could not list consumer groups: $($_.Exception.Message)" -ForegroundColor Red
}