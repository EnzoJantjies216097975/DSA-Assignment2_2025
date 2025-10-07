# Setup Config.toml files for all services
# Save as: setup-configs.ps1

Write-Host "Setting up Config.toml files for all services..." -ForegroundColor Cyan
Write-Host ""

# Passenger Service Config
$passengerConfig = @"
# Passenger Service Configuration
mongoHost = "mongodb"
mongoPort = 27017
mongoUsername = "admin"
mongoPassword = "password123"
mongoDatabase = "transport_db"
"@

Write-Host "Creating passenger-service/Config.toml..." -ForegroundColor Yellow
Set-Content -Path "passenger-service/Config.toml" -Value $passengerConfig
Write-Host "[OK] Created" -ForegroundColor Green

# Transport Service Config
$transportConfig = @"
# Transport Service Configuration
mongoHost = "mongodb"
mongoPort = 27017
mongoUsername = "admin"
mongoPassword = "password123"
mongoDatabase = "transport_db"
kafkaBootstrapServers = "kafka:9092"
"@

Write-Host "Creating transport-service/Config.toml..." -ForegroundColor Yellow
Set-Content -Path "transport-service/Config.toml" -Value $transportConfig
Write-Host "[OK] Created" -ForegroundColor Green

# Ticketing Service Config
$ticketingConfig = @"
# Ticketing Service Configuration
mongoHost = "mongodb"
mongoPort = 27017
mongoUsername = "admin"
mongoPassword = "password123"
mongoDatabase = "transport_db"
kafkaBootstrapServers = "kafka:9092"
"@

Write-Host "Creating ticketing-service/Config.toml..." -ForegroundColor Yellow
Set-Content -Path "ticketing-service/Config.toml" -Value $ticketingConfig
Write-Host "[OK] Created" -ForegroundColor Green

# Payment Service Config
$paymentConfig = @"
# Payment Service Configuration
mongoHost = "mongodb"
mongoPort = 27017
mongoUsername = "admin"
mongoPassword = "password123"
mongoDatabase = "transport_db"
kafkaBootstrapServers = "kafka:9092"
ticketingServiceUrl = "http://ticketing-service:9092"
"@

Write-Host "Creating payment-service/Config.toml..." -ForegroundColor Yellow
Set-Content -Path "payment-service/Config.toml" -Value $paymentConfig
Write-Host "[OK] Created" -ForegroundColor Green

# Notification Service Config
$notificationConfig = @"
# Notification Service Configuration
mongoHost = "mongodb"
mongoPort = 27017
mongoUsername = "admin"
mongoPassword = "password123"
mongoDatabase = "transport_db"
kafkaBootstrapServers = "kafka:9092"
emailEnabled = false
smtpHost = "smtp.example.com"
smtpPort = 587
smtpUsername = "noreply@transport.com"
smtpPassword = "password"
smsEnabled = false
smsApiUrl = "https://api.sms-provider.com"
smsApiKey = "your-api-key"
"@

Write-Host "Creating notification-service/Config.toml..." -ForegroundColor Yellow
Set-Content -Path "notification-service/Config.toml" -Value $notificationConfig
Write-Host "[OK] Created" -ForegroundColor Green

# Admin Service Config
$adminConfig = @"
# Admin Service Configuration
mongoHost = "mongodb"
mongoPort = 27017
mongoUsername = "admin"
mongoPassword = "password123"
mongoDatabase = "transport_db"
transportServiceUrl = "http://transport-service:9091"
ticketingServiceUrl = "http://ticketing-service:9092"
"@

Write-Host "Creating admin-service/Config.toml..." -ForegroundColor Yellow
Set-Content -Path "admin-service/Config.toml" -Value $adminConfig
Write-Host "[OK] Created" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "All Config.toml files created!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Restart your services: docker-compose down && docker-compose up -d" -ForegroundColor White
Write-Host "2. Wait 30 seconds for services to start" -ForegroundColor White
Write-Host "3. Run the demo: .\demo.ps1" -ForegroundColor White
Write-Host ""