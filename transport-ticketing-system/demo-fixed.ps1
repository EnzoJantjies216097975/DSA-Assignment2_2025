# Save as demo-fixed.ps1

Write-Host "Transport Ticketing System Demo (FIXED)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check services
Write-Host "Checking services..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost:9090/passenger/health" -Method Get -TimeoutSec 5
    Write-Host "[OK] Passenger Service: $health" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Passenger service not available" -ForegroundColor Red
    exit
}

# Generate unique email
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$email = "fixed$timestamp@test.com"

# 1. Register User
Write-Host "`nStep 1: Registering user..." -ForegroundColor Yellow
try {
    $registerBody = @{
        email = $email
        password = "demo123"
        firstName = "Demo"
        lastName = "User"
        phone = "+264811111111"
    } | ConvertTo-Json
    
    $user = Invoke-RestMethod -Uri "http://localhost:9090/passenger/register" `
        -Method Post `
        -ContentType "application/json" `
        -Body $registerBody
        
    Write-Host "[SUCCESS] User registered: $($user.userId)" -ForegroundColor Green
    Write-Host "          Email: $email" -ForegroundColor Gray
    $userId = $user.userId
} catch {
    Write-Host "[ERROR] Registration failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# 2. Login
Write-Host "`nStep 2: Logging in..." -ForegroundColor Yellow
try {
    $loginBody = @{
        email = $email
        password = "demo123"
    } | ConvertTo-Json
    
    $login = Invoke-RestMethod -Uri "http://localhost:9090/passenger/login" `
        -Method Post `
        -ContentType "application/json" `
        -Body $loginBody
        
    Write-Host "[SUCCESS] Login successful!" -ForegroundColor Green
    Write-Host "          Welcome, $($login.firstName) $($login.lastName)!" -ForegroundColor Gray
} catch {
    Write-Host "[ERROR] Login failed: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. Create Route
Write-Host "`nStep 3: Creating bus route..." -ForegroundColor Yellow
try {
    $routeBody = @{
        routeNumber = "FIX1"
        routeName = "Windhoek CBD to Katutura"
        startPoint = "CBD"
        endPoint = "Katutura"
        stops = @("CBD", "Wanaheda", "Katutura")
        transportType = "BUS"
    } | ConvertTo-Json
    
    $route = Invoke-RestMethod -Uri "http://localhost:9091/transport/routes" `
        -Method Post `
        -ContentType "application/json" `
        -Body $routeBody
        
    Write-Host "[SUCCESS] Route created: $($route.routeId)" -ForegroundColor Green
    Write-Host "          Route: FIX1 - Windhoek CBD to Katutura" -ForegroundColor Gray
    $routeId = $route.routeId
} catch {
    Write-Host "[ERROR] Failed to create route: $($_.Exception.Message)" -ForegroundColor Red
}

# 4. Create Trip
Write-Host "`nStep 4: Scheduling trip..." -ForegroundColor Yellow
try {
    $tripBody = @{
        routeId = $routeId
        departureTime = "15:00"
        arrivalTime = "15:45"
        date = "2025-10-08"
        totalSeats = 35
    } | ConvertTo-Json
    
    $trip = Invoke-RestMethod -Uri "http://localhost:9091/transport/trips" `
        -Method Post `
        -ContentType "application/json" `
        -Body $tripBody
        
    Write-Host "[SUCCESS] Trip created: $($trip.tripId)" -ForegroundColor Green
    Write-Host "          Departure: 15:00 | Arrival: 15:45 | Seats: 35" -ForegroundColor Gray
    $tripId = $trip.tripId
} catch {
    Write-Host "[ERROR] Failed to create trip: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Purchase Ticket
Write-Host "`nStep 5: Purchasing ticket..." -ForegroundColor Yellow
try {
    $ticketBody = @{
        userId = $userId
        tripId = $tripId
        ticketType = "SINGLE_RIDE"
        paymentMethod = "CREDIT_CARD"
    } | ConvertTo-Json
    
    $ticket = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/tickets/purchase" `
        -Method Post `
        -ContentType "application/json" `
        -Body $ticketBody
        
    Write-Host "[SUCCESS] Ticket purchased: $($ticket.ticketId)" -ForegroundColor Green
    Write-Host "          Price: N`$$($ticket.price) | Status: $($ticket.status)" -ForegroundColor Gray
    Write-Host ""
    $ticketId = $ticket.ticketId
} catch {
    Write-Host "[ERROR] Failed to purchase ticket: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# 5b. Manual Payment Processing
# 5b. Manual Payment Processing - FIXED
Write-Host "Step 5b: Processing payment manually..." -ForegroundColor Yellow
try {
    $paymentBody = @{
        ticketId = $ticketId
        userId = $userId
        amount = 15.00
        paymentMethod = "CREDIT_CARD"
    } | ConvertTo-Json
    
    $payment = Invoke-RestMethod -Uri "http://localhost:9093/payment/payments/process" `
        -Method Post `
        -ContentType "application/json" `
        -Body $paymentBody
        
    Write-Host "[SUCCESS] Payment processed!" -ForegroundColor Green
    Write-Host "          Payment ID: $($payment.paymentId)" -ForegroundColor Gray
    Write-Host "          Status: $($payment.status)" -ForegroundColor Gray
    
    # Update ticket status in MongoDB - FIXED COMMAND
    Write-Host "          Updating ticket status to PAID..." -ForegroundColor Gray
    
    # Create a JavaScript file for the update command
    $jsCommand = @"
use transport_db;
var result = db.tickets.updateOne(
    {id: '$ticketId'}, 
    {
        `$set: { 
            status: 'PAID', 
            paymentId: '$($payment.paymentId)', 
            updatedAt: new Date().toISOString() 
        }
    }
);
if (result.modifiedCount === 1) {
    print('SUCCESS: Ticket status updated to PAID');
} else {
    print('ERROR: Ticket not found or not updated. Matched: ' + result.matchedCount + ', Modified: ' + result.modifiedCount);
}
"@

    $jsCommand | Out-File -FilePath "update_ticket.js" -Encoding utf8
    
    $updateResult = docker exec -i mongodb mongosh -u admin -p password123 --quiet --file update_ticket.js 2>&1
    Remove-Item update_ticket.js -ErrorAction SilentlyContinue
    
    Write-Host "          $updateResult" -ForegroundColor Gray
    
    # Wait for the update to complete
    Start-Sleep -Seconds 2
    
    # Verify the update worked
    $verifyResult = docker exec -i mongodb mongosh -u admin -p password123 --quiet --eval "
        use transport_db;
        var ticket = db.tickets.findOne({id: '$ticketId'});
        if (ticket) {
            print('VERIFY: Ticket status is ' + ticket.status);
        } else {
            print('VERIFY: Ticket not found');
        }
    " 2>&1
    
    Write-Host "          $verifyResult" -ForegroundColor Gray
    
} catch {
    Write-Host "[ERROR] Manual payment failed: $($_.Exception.Message)" -ForegroundColor Red
}
# 6. Wait a moment
Write-Host "`nStep 6: Waiting for updates..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

# 7. Check Ticket Status
Write-Host "`nStep 7: Checking ticket status..." -ForegroundColor Yellow
try {
    $ticketStatus = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/tickets/$ticketId" -Method Get
    Write-Host "[SUCCESS] Ticket status: $($ticketStatus.status)" -ForegroundColor $(if($ticketStatus.status -eq "PAID"){"Green"}else{"Yellow"})
    
    if ($ticketStatus.status -eq "PAID") {
        Write-Host "          Payment successful! Ready to board." -ForegroundColor Green
    } else {
        Write-Host "          Payment status: $($ticketStatus.status)" -ForegroundColor Yellow
    }
    Write-Host ""
} catch {
    Write-Host "[ERROR] Failed to check ticket status: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

# 8. Validate Ticket (Boarding) - Only if paid
Write-Host "Step 8: Validating ticket at boarding..." -ForegroundColor Yellow
try {
    $validationBody = @{
        ticketId = $ticketId
        validatorId = "validator-demo-001"
        tripId = $tripId
    } | ConvertTo-Json
    
    $validation = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/tickets/validate" `
        -Method Post `
        -ContentType "application/json" `
        -Body $validationBody
        
    Write-Host "[SUCCESS] $($validation.message)" -ForegroundColor Green
    Write-Host "          Validated by: validator-demo-001" -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Host "[ERROR] Failed to validate ticket: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

# 9. View User's Tickets
Write-Host "Step 9: Fetching user's tickets..." -ForegroundColor Yellow
try {
    $userTickets = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/users/$userId/tickets" -Method Get
    Write-Host "[SUCCESS] User has $($userTickets.Count) ticket(s)" -ForegroundColor Green
    foreach ($t in $userTickets) {
        $color = if($t.status -eq "PAID"){"Green"}elseif($t.status -eq "USED"){"Yellow"}else{"Red"}
        Write-Host "          - $($t.ticketType) | Status: $($t.status) | Price: N`$$($t.price)" -ForegroundColor $color
    }
    Write-Host ""
} catch {
    Write-Host "[ERROR] Failed to fetch user tickets: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "DEMO COMPLETE (Manual Payment Processing)" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan