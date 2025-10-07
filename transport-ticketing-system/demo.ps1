# Save this as demo.ps1 (overwrite the existing file)

Write-Host "Transport Ticketing System Demo" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# Check if services are running
Write-Host "Checking if services are running..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost:9090/passenger/health" -Method Get -TimeoutSec 5
    Write-Host "[OK] Services are running" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "[ERROR] Services are not responding. Please start them with: docker-compose up -d" -ForegroundColor Red
    exit
}

# Generate unique email for demo
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$email = "demo$timestamp@test.com"

# 1. Register User
Write-Host "Step 1: Registering user..." -ForegroundColor Yellow
try {
    $user = Invoke-RestMethod -Uri "http://localhost:9090/passenger/register" `
        -Method Post `
        -ContentType "application/json" `
        -Body "{`"email`":`"$email`",`"password`":`"demo123`",`"firstName`":`"Demo`",`"lastName`":`"User`",`"phone`":`"+264811111111`"}"
    Write-Host "[SUCCESS] User registered: $($user.userId)" -ForegroundColor Green
    Write-Host "          Email: $email" -ForegroundColor Gray
    Write-Host ""
    $userId = $user.userId
} catch {
    Write-Host "[ERROR] Failed to register user: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# 2. Login
Write-Host "Step 2: Logging in..." -ForegroundColor Yellow
try {
    $login = Invoke-RestMethod -Uri "http://localhost:9090/passenger/login" `
        -Method Post `
        -ContentType "application/json" `
        -Body "{`"email`":`"$email`",`"password`":`"demo123`"}"
    Write-Host "[SUCCESS] Login successful!" -ForegroundColor Green
    Write-Host "          Welcome, $($login.firstName) $($login.lastName)!" -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Host "[ERROR] Failed to login: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. Create Route
Write-Host "Step 3: Creating bus route..." -ForegroundColor Yellow
try {
    $route = Invoke-RestMethod -Uri "http://localhost:9091/transport/routes" `
        -Method Post `
        -ContentType "application/json" `
        -Body '{"routeNumber":"DEMO1","routeName":"Windhoek CBD to Airport","startPoint":"CBD","endPoint":"Airport","stops":["CBD","Klein Windhoek","Eros","Airport"],"transportType":"BUS"}'
    Write-Host "[SUCCESS] Route created: $($route.routeId)" -ForegroundColor Green
    Write-Host "          Route: DEMO1 - Windhoek CBD to Airport" -ForegroundColor Gray
    Write-Host ""
    $routeId = $route.routeId
} catch {
    Write-Host "[ERROR] Failed to create route: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# 4. Create Trip
Write-Host "Step 4: Scheduling trip..." -ForegroundColor Yellow
try {
    $tripBody = @{
        routeId = $routeId
        departureTime = "10:00"
        arrivalTime = "11:00"
        date = "2025-10-08"
        totalSeats = 40
    } | ConvertTo-Json
    
    $trip = Invoke-RestMethod -Uri "http://localhost:9091/transport/trips" `
        -Method Post `
        -ContentType "application/json" `
        -Body $tripBody
    Write-Host "[SUCCESS] Trip created: $($trip.tripId)" -ForegroundColor Green
    Write-Host "          Departure: 10:00 | Arrival: 11:00 | Seats: 40" -ForegroundColor Gray
    Write-Host ""
    $tripId = $trip.tripId
} catch {
    Write-Host "[ERROR] Failed to create trip: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# 5. Purchase Ticket
Write-Host "Step 5: Purchasing ticket..." -ForegroundColor Yellow
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

# 6. Wait for Payment Processing
Write-Host "Step 6: Processing payment..." -ForegroundColor Yellow
Write-Host "          Simulating payment gateway (5 seconds)..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# 7. Check Ticket Status
Write-Host ""
Write-Host "Step 7: Checking ticket status..." -ForegroundColor Yellow
try {
    $ticketStatus = Invoke-RestMethod -Uri "http://localhost:9096/ticketing/tickets/$ticketId" -Method Get
    Write-Host "[SUCCESS] Ticket status updated: $($ticketStatus.status)" -ForegroundColor $(if($ticketStatus.status -eq "PAID"){"Green"}else{"Red"})
    
    if ($ticketStatus.status -eq "PAID") {
        Write-Host "          Payment successful! Ready to board." -ForegroundColor Green
    } else {
        Write-Host "          Payment still processing or failed." -ForegroundColor Yellow
    }
    Write-Host ""
} catch {
    Write-Host "[ERROR] Failed to check ticket status: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

# 8. Validate Ticket (Boarding)
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
        Write-Host "          - $($t.ticketType) | Status: $($t.status) | Price: N`$$($t.price)" -ForegroundColor Gray
    }
    Write-Host ""
} catch {
    Write-Host "[ERROR] Failed to fetch user tickets: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

# 10. Admin Dashboard
Write-Host "Step 10: Fetching admin dashboard..." -ForegroundColor Yellow
try {
    $dashboard = Invoke-RestMethod -Uri "http://localhost:9095/admin/dashboard" -Method Get
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "         ADMIN DASHBOARD" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "  Total Routes:     $($dashboard.totalRoutes)" -ForegroundColor Cyan
    Write-Host "  Total Trips:      $($dashboard.totalTrips)" -ForegroundColor Cyan
    Write-Host "  Total Tickets:    $($dashboard.totalTickets)" -ForegroundColor Cyan
    Write-Host "  Total Revenue:   N`$$($dashboard.totalRevenue)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host ""
} catch {
    Write-Host "[ERROR] Failed to fetch dashboard: $($_.Exception.Message)" -ForegroundColor Red
}

# 11. View Notification Logs
Write-Host "Step 11: Checking notification logs..." -ForegroundColor Yellow
Write-Host "         (Showing last 20 lines from notification service)" -ForegroundColor Gray
try {
    docker-compose logs --tail=20 notification-service 2>$null
} catch {
    Write-Host "         Could not fetch logs" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "    DEMO COMPLETE!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "What happened:" -ForegroundColor Yellow
Write-Host "  1. User registered and logged in"
Write-Host "  2. Route and trip created"
Write-Host "  3. Ticket purchased (event published to Kafka)"
Write-Host "  4. Payment processed automatically (Kafka consumer)"
Write-Host "  5. Ticket validated for boarding"
Write-Host "  6. Notifications sent (check logs above)"
Write-Host "  7. Dashboard updated with stats"
Write-Host ""
Write-Host "This demonstrates the complete distributed system flow!" -ForegroundColor Green
Write-Host ""