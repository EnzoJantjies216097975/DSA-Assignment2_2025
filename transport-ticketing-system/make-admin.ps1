# Make User Admin Script
# Save as: make-admin.ps1

Write-Host "================================" -ForegroundColor Cyan
Write-Host "  PROMOTE USER TO ADMIN" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Get MongoDB container name dynamically
Write-Host "Finding MongoDB container..." -ForegroundColor Gray
$mongoContainer = docker ps --format "{{.Names}}" | Select-String -Pattern "mongodb|mongo" | Select-Object -First 1

if (-not $mongoContainer) {
    Write-Host "[ERROR] MongoDB container not found" -ForegroundColor Red
    Write-Host ""
    Write-Host "Available containers:" -ForegroundColor Yellow
    docker ps --format "{{.Names}}" | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
    Write-Host ""
    Write-Host "Please ensure:" -ForegroundColor Yellow
    Write-Host "- Docker is running" -ForegroundColor White
    Write-Host "- Services are started: docker-compose up -d" -ForegroundColor White
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

$mongoContainer = $mongoContainer.ToString()
Write-Host "[OK] Found MongoDB container: $mongoContainer" -ForegroundColor Green
Write-Host ""

# Get user email
$username = Read-Host "Enter the username/email of the user to promote"

if ([string]::IsNullOrWhiteSpace($username)) {
    Write-Host "[ERROR] Username cannot be empty" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

Write-Host ""
Write-Host "Attempting to promote user: $username" -ForegroundColor Yellow
Write-Host ""

# Create MongoDB command
$mongoCommand = @"
use transport_db
var result = db.users.updateOne(
  {email: "$username"},
  {`$set: {role: "ADMIN"}}
)
if (result.matchedCount === 0) {
  print("ERROR: User not found with username: $username")
} else if (result.modifiedCount === 0) {
  print("INFO: User already has ADMIN role")
} else {
  print("SUCCESS: User promoted to ADMIN")
}
db.users.findOne({email: "$username"}, {email: 1, role: 1, firstName: 1, lastName: 1, _id: 0})
"@

# Execute MongoDB command
try {
    Write-Host "Connecting to MongoDB..." -ForegroundColor Gray
    $result = docker exec -i $mongoContainer mongosh -u admin -p password123 --quiet --eval $mongoCommand 2>&1
    
    Write-Host ""
    Write-Host "MongoDB Response:" -ForegroundColor Cyan
    Write-Host $result
    Write-Host ""
    
    if ($result -match "SUCCESS") {
        Write-Host "✓ User successfully promoted to ADMIN" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "1. The user should logout if currently logged in" -ForegroundColor White
        Write-Host "2. Login again to refresh their session" -ForegroundColor White
        Write-Host "3. Select '1. Admin' when logging in" -ForegroundColor White
        Write-Host "4. They will now have access to the Admin Portal" -ForegroundColor White
    } elseif ($result -match "ERROR: User not found") {
        Write-Host "✗ User not found with username: $username" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please ensure:" -ForegroundColor Yellow
        Write-Host "- The username is correct (case-sensitive)" -ForegroundColor White
        Write-Host "- The user has registered in the system" -ForegroundColor White
        Write-Host "- Run: .\list-users.ps1 to see all registered users" -ForegroundColor White
    } elseif ($result -match "INFO: User already has ADMIN role") {
        Write-Host "ℹ User already has ADMIN role" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "This user can already login as Admin!" -ForegroundColor Green
    }
    
} catch {
    Write-Host "✗ Failed to connect to MongoDB" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please ensure:" -ForegroundColor Yellow
    Write-Host "- Docker is running" -ForegroundColor White
    Write-Host "- MongoDB container is running: docker-compose ps" -ForegroundColor White
    Write-Host "- Services are healthy: docker ps" -ForegroundColor White
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Read-Host "Press Enter to exit"