# Create First Admin User
# Save as: create-first-admin.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CREATE FIRST ADMIN USER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check services
Write-Host "Checking services..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost:9090/passenger/health" -Method Get -TimeoutSec 5
    Write-Host "[OK] Services are running" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Services are not running!" -ForegroundColor Red
    Write-Host "Please start services: docker-compose up -d" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit
}

Write-Host ""
Write-Host "Let's create your first admin user!" -ForegroundColor Cyan
Write-Host ""

# Get user details
$email = Read-Host "Enter email/username (e.g., admin@windhoek.gov.na)"
$password = Read-Host "Enter password" -AsSecureString
$passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
$confirmPassword = Read-Host "Confirm password" -AsSecureString
$confirmPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword))

if ($passwordPlain -ne $confirmPasswordPlain) {
    Write-Host ""
    Write-Host "[ERROR] Passwords do not match!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

$firstName = Read-Host "Enter first name"
$lastName = Read-Host "Enter last name"
$phone = Read-Host "Enter phone number (e.g., +264811234567)"

Write-Host ""
Write-Host "Creating user..." -ForegroundColor Yellow

# Register user
try {
    $body = @{
        email = $email
        password = $passwordPlain
        firstName = $firstName
        lastName = $lastName
        phone = $phone
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri "http://localhost:9090/passenger/register" `
        -Method Post `
        -ContentType "application/json" `
        -Body $body
    
    Write-Host "[SUCCESS] User registered!" -ForegroundColor Green
    Write-Host "User ID: $($response.userId)" -ForegroundColor Gray
    Write-Host ""
    
} catch {
    Write-Host "[ERROR] Registration failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "This might mean:" -ForegroundColor Yellow
    Write-Host "- User already exists with this email" -ForegroundColor White
    Write-Host "- Services not fully started (wait 30 seconds and try again)" -ForegroundColor White
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

# Promote to admin
Write-Host "Promoting user to ADMIN..." -ForegroundColor Yellow

$mongoContainer = docker ps --format "{{.Names}}" | Select-String -Pattern "mongodb|mongo" | Select-Object -First 1

if (-not $mongoContainer) {
    Write-Host "[ERROR] MongoDB container not found!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

$mongoContainer = $mongoContainer.ToString()

try {
    $mongoCommand = "use transport_db; db.users.updateOne({email: `"$email`"}, {`$set: {role: `"ADMIN`"}})"
    $result = docker exec -i $mongoContainer mongosh -u admin -p password123 --quiet --eval $mongoCommand 2>&1
    
    Write-Host "[SUCCESS] User promoted to ADMIN!" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "[ERROR] Failed to promote user" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

# Verify
Write-Host "Verifying admin user..." -ForegroundColor Yellow
$mongoCommand = "use transport_db; db.users.findOne({email: `"$email`"}, {email: 1, role: 1, firstName: 1, lastName: 1, _id: 0})"
$user = docker exec -i $mongoContainer mongosh -u admin -p password123 --quiet --eval $mongoCommand 2>&1

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ADMIN USER CREATED!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "User Details:" -ForegroundColor Cyan
Write-Host "  Username: $email" -ForegroundColor White
Write-Host "  Name: $firstName $lastName" -ForegroundColor White
Write-Host "  Role: ADMIN" -ForegroundColor Magenta
Write-Host "  Phone: $phone" -ForegroundColor White
Write-Host ""
Write-Host "You can now login!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\client.ps1" -ForegroundColor White
Write-Host "2. Select: 1. Admin" -ForegroundColor White
Write-Host "3. Username: $email" -ForegroundColor White
Write-Host "4. Password: [the password you just set]" -ForegroundColor White
Write-Host ""

Read-Host "Press Enter to exit"