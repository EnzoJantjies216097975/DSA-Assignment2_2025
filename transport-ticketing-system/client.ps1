# Interactive Transport Ticketing System Client
# Save as: interactive-client.ps1

# Global variables to store session data
$Global:CurrentUser = $null
$Global:IsAdmin = $false

# Color functions
function Write-Title {
    param([string]$Text)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "[SUCCESS] $Text" -ForegroundColor Green
}

function Write-Error {
    param([string]$Text)
    Write-Host "[ERROR] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor Yellow
}

# Check if services are running
function Test-ServicesRunning {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:9090/passenger/health" -Method Get -TimeoutSec 5
        return $true
    } catch {
        Write-Error "Services are not running! Please start with: docker-compose up -d"
        return $false
    }
}

# Passenger Functions
function Register-User {
    Write-Title "USER REGISTRATION"
    
    $email = Read-Host "Enter email"
    $password = Read-Host "Enter password" -AsSecureString
    $passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    $firstName = Read-Host "Enter first name"
    $lastName = Read-Host "Enter last name"
    $phone = Read-Host "Enter phone number"
    
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
        
        Write-Success "Registration successful!"
        Write-Host "User ID: $($response.userId)" -ForegroundColor Gray
        Write-Host "Email: $($response.email)" -ForegroundColor Gray
        
    } catch {
        Write-Error "Registration failed: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Login-User {
    Write-Title "USER LOGIN"
    
    $email = Read-Host "Enter email"
    $password = Read-Host "Enter password" -AsSecureString
    $passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    
    try {
        $body = @{
            email = $email
            password = $passwordPlain
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "http://localhost:9090/passenger/login" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body
        
        $Global:CurrentUser = @{
            UserId = $response.userId
            Email = $response.email
            FirstName = $response.firstName
            LastName = $response.lastName
        }
        
        Write-Success "Login successful!"
        Write-Host "Welcome, $($response.firstName) $($response.lastName)!" -ForegroundColor Cyan
        
    } catch {
        Write-Error "Login failed: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-Routes {
    Write-Title "AVAILABLE ROUTES"
    
    try {
        $routes = Invoke-RestMethod -Uri "http://localhost:9091/transport/routes" -Method Get
        
        if ($routes.Count -eq 0) {
            Write-Info "No routes available"
        } else {
            foreach ($route in $routes) {
                Write-Host "`nRoute: $($route.routeNumber) - $($route.routeName)" -ForegroundColor Cyan
                Write-Host "  From: $($route.startPoint)" -ForegroundColor Gray
                Write-Host "  To: $($route.endPoint)" -ForegroundColor Gray
                Write-Host "  Type: $($route.transportType)" -ForegroundColor Gray
                Write-Host "  Stops: $($route.stops -join ', ')" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Error "Failed to fetch routes: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-Trips {
    Write-Title "AVAILABLE TRIPS"
    
    try {
        $trips = Invoke-RestMethod -Uri "http://localhost:9091/transport/trips" -Method Get
        
        if ($trips.Count -eq 0) {
            Write-Info "No trips available"
        } else {
            foreach ($trip in $trips) {
                Write-Host "`nTrip ID: $($trip.id)" -ForegroundColor Cyan
                Write-Host "  Route: $($trip.routeId)" -ForegroundColor Gray
                Write-Host "  Date: $($trip.date)" -ForegroundColor Gray
                Write-Host "  Departure: $($trip.departureTime)" -ForegroundColor Gray
                Write-Host "  Arrival: $($trip.arrivalTime)" -ForegroundColor Gray
                Write-Host "  Status: $($trip.status)" -ForegroundColor Gray
                Write-Host "  Available Seats: $($trip.availableSeats)/$($trip.totalSeats)" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Error "Failed to fetch trips: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Purchase-Ticket {
    if ($null -eq $Global:CurrentUser) {
        Write-Error "Please login first!"
        Read-Host "Press Enter to continue"
        return
    }
    
    Write-Title "PURCHASE TICKET"
    
    Write-Host "`nTicket Types:" -ForegroundColor Yellow
    Write-Host "1. SINGLE_RIDE (N`$15.00)"
    Write-Host "2. MULTIPLE_RIDE (N`$120.00 - 10 rides)"
    Write-Host "3. DAILY_PASS (N`$50.00)"
    Write-Host "4. WEEKLY_PASS (N`$300.00)"
    Write-Host "5. MONTHLY_PASS (N`$1000.00)"
    
    $choice = Read-Host "`nSelect ticket type (1-5)"
    
    $ticketTypes = @("SINGLE_RIDE", "MULTIPLE_RIDE", "DAILY_PASS", "WEEKLY_PASS", "MONTHLY_PASS")
    $ticketType = $ticketTypes[[int]$choice - 1]
    
    $tripId = Read-Host "Enter Trip ID (or press Enter to skip)"
    if ($tripId -eq "") { $tripId = $null }
    
    try {
        $body = @{
            userId = $Global:CurrentUser.UserId
            tripId = $tripId
            ticketType = $ticketType
            paymentMethod = "CREDIT_CARD"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "http://localhost:9092/ticketing/tickets/purchase" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body
        
        Write-Success "Ticket purchased!"
        Write-Host "Ticket ID: $($response.ticketId)" -ForegroundColor Cyan
        Write-Host "Price: N`$$($response.price)" -ForegroundColor Cyan
        Write-Host "Status: $($response.status)" -ForegroundColor Yellow
        Write-Host "`nPayment is being processed automatically..." -ForegroundColor Gray
        
    } catch {
        Write-Error "Purchase failed: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-MyTickets {
    if ($null -eq $Global:CurrentUser) {
        Write-Error "Please login first!"
        Read-Host "Press Enter to continue"
        return
    }
    
    Write-Title "MY TICKETS"
    
    try {
        $tickets = Invoke-RestMethod -Uri "http://localhost:9092/ticketing/users/$($Global:CurrentUser.UserId)/tickets" -Method Get
        
        if ($tickets.Count -eq 0) {
            Write-Info "You have no tickets"
        } else {
            foreach ($ticket in $tickets) {
                Write-Host "`nTicket ID: $($ticket.id)" -ForegroundColor Cyan
                Write-Host "  Type: $($ticket.ticketType)" -ForegroundColor Gray
                Write-Host "  Status: $($ticket.status)" -ForegroundColor $(if($ticket.status -eq "PAID"){"Green"}else{"Yellow"})
                Write-Host "  Price: N`$$($ticket.price)" -ForegroundColor Gray
                Write-Host "  Valid From: $($ticket.validFrom)" -ForegroundColor Gray
                Write-Host "  Valid Until: $($ticket.validUntil)" -ForegroundColor Gray
                if ($ticket.ridesRemaining) {
                    Write-Host "  Rides Remaining: $($ticket.ridesRemaining)" -ForegroundColor Gray
                }
            }
        }
    } catch {
        Write-Error "Failed to fetch tickets: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Validate-Ticket {
    Write-Title "VALIDATE TICKET"
    
    $ticketId = Read-Host "Enter Ticket ID"
    $validatorId = Read-Host "Enter Validator ID"
    $tripId = Read-Host "Enter Trip ID (optional, press Enter to skip)"
    if ($tripId -eq "") { $tripId = $null }
    
    try {
        $body = @{
            ticketId = $ticketId
            validatorId = $validatorId
            tripId = $tripId
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "http://localhost:9092/ticketing/tickets/validate" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body
        
        Write-Success $response.message
        if ($response.ridesRemaining) {
            Write-Host "Rides Remaining: $($response.ridesRemaining)" -ForegroundColor Cyan
        }
        
    } catch {
        Write-Error "Validation failed: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

# Admin Functions
function Create-Route {
    Write-Title "CREATE ROUTE"
    
    $routeNumber = Read-Host "Enter route number"
    $routeName = Read-Host "Enter route name"
    $startPoint = Read-Host "Enter start point"
    $endPoint = Read-Host "Enter end point"
    $stopsInput = Read-Host "Enter stops (comma-separated)"
    $stops = $stopsInput -split ',' | ForEach-Object { $_.Trim() }
    
    Write-Host "`nTransport Type:" -ForegroundColor Yellow
    Write-Host "1. BUS"
    Write-Host "2. TRAIN"
    $typeChoice = Read-Host "Select type (1-2)"
    $transportType = if ($typeChoice -eq "1") { "BUS" } else { "TRAIN" }
    
    try {
        $body = @{
            routeNumber = $routeNumber
            routeName = $routeName
            startPoint = $startPoint
            endPoint = $endPoint
            stops = $stops
            transportType = $transportType
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "http://localhost:9091/transport/routes" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body
        
        Write-Success "Route created!"
        Write-Host "Route ID: $($response.routeId)" -ForegroundColor Cyan
        
    } catch {
        Write-Error "Failed to create route: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Create-Trip {
    Write-Title "CREATE TRIP"
    
    $routeId = Read-Host "Enter Route ID"
    $date = Read-Host "Enter date (YYYY-MM-DD)"
    $departureTime = Read-Host "Enter departure time (HH:MM)"
    $arrivalTime = Read-Host "Enter arrival time (HH:MM)"
    $totalSeats = Read-Host "Enter total seats"
    
    try {
        $body = @{
            routeId = $routeId
            date = $date
            departureTime = $departureTime
            arrivalTime = $arrivalTime
            totalSeats = [int]$totalSeats
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "http://localhost:9091/transport/trips" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body
        
        Write-Success "Trip created!"
        Write-Host "Trip ID: $($response.tripId)" -ForegroundColor Cyan
        
    } catch {
        Write-Error "Failed to create trip: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Update-TripStatus {
    Write-Title "UPDATE TRIP STATUS"
    
    $tripId = Read-Host "Enter Trip ID"
    
    Write-Host "`nStatus Options:" -ForegroundColor Yellow
    Write-Host "1. DELAYED"
    Write-Host "2. CANCELLED"
    Write-Host "3. IN_PROGRESS"
    Write-Host "4. COMPLETED"
    
    $choice = Read-Host "Select status (1-4)"
    $statuses = @("DELAYED", "CANCELLED", "IN_PROGRESS", "COMPLETED")
    $status = $statuses[[int]$choice - 1]
    
    $reason = Read-Host "Enter reason"
    
    try {
        $body = @{
            status = $status
            reason = $reason
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "http://localhost:9091/transport/trips/$tripId/status" `
            -Method Patch `
            -ContentType "application/json" `
            -Body $body
        
        Write-Success "Trip status updated!"
        Write-Host "Notifications sent to affected passengers" -ForegroundColor Gray
        
    } catch {
        Write-Error "Failed to update trip: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-Dashboard {
    Write-Title "ADMIN DASHBOARD"
    
    try {
        $dashboard = Invoke-RestMethod -Uri "http://localhost:9095/admin/dashboard" -Method Get
        
        Write-Host "`nSystem Statistics:" -ForegroundColor Cyan
        Write-Host "  Total Routes:  $($dashboard.totalRoutes)" -ForegroundColor White
        Write-Host "  Total Trips:   $($dashboard.totalTrips)" -ForegroundColor White
        Write-Host "  Total Tickets: $($dashboard.totalTickets)" -ForegroundColor White
        Write-Host "  Total Revenue: N`$$($dashboard.totalRevenue)" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed to fetch dashboard: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-SalesReport {
    Write-Title "SALES REPORT"
    
    try {
        $report = Invoke-RestMethod -Uri "http://localhost:9095/admin/reports/sales" -Method Get
        
        Write-Host "`nSales Summary:" -ForegroundColor Cyan
        Write-Host "  Total Tickets Sold: $($report.totalTicketsSold)" -ForegroundColor White
        Write-Host "  Total Revenue: N`$$($report.totalRevenue)" -ForegroundColor Green
        
        Write-Host "`nBreakdown by Ticket Type:" -ForegroundColor Cyan
        foreach ($type in $report.ticketsByType.PSObject.Properties) {
            $revenue = $report.revenueByType.($type.Name)
            Write-Host "  $($type.Name): $($type.Value) tickets (N`$$revenue)" -ForegroundColor White
        }
        
        Write-Host "`nReport Date: $($report.reportDate)" -ForegroundColor Gray
        
    } catch {
        Write-Error "Failed to generate report: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-TrafficReport {
    Write-Title "TRAFFIC REPORT"
    
    try {
        $report = Invoke-RestMethod -Uri "http://localhost:9095/admin/reports/traffic" -Method Get
        
        Write-Host "`nTraffic Summary:" -ForegroundColor Cyan
        Write-Host "  Total Passengers: $($report.totalPassengers)" -ForegroundColor White
        
        Write-Host "`nPassengers by Route:" -ForegroundColor Cyan
        foreach ($route in $report.passengersByRoute.PSObject.Properties) {
            Write-Host "  Route $($route.Name): $($route.Value) passengers" -ForegroundColor White
        }
        
        Write-Host "`nReport Date: $($report.reportDate)" -ForegroundColor Gray
        
    } catch {
        Write-Error "Failed to generate report: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

# Menu Functions
function Show-PassengerMenu {
    while ($true) {
        Clear-Host
        Write-Title "PASSENGER MENU"
        
        if ($null -ne $Global:CurrentUser) {
            Write-Host "Logged in as: $($Global:CurrentUser.FirstName) $($Global:CurrentUser.LastName)" -ForegroundColor Green
            Write-Host "Email: $($Global:CurrentUser.Email)" -ForegroundColor Gray
        } else {
            Write-Host "Not logged in" -ForegroundColor Yellow
        }
        
        Write-Host "`n1. Register"
        Write-Host "2. Login"
        Write-Host "3. View Routes"
        Write-Host "4. View Trips"
        Write-Host "5. Purchase Ticket"
        Write-Host "6. My Tickets"
        Write-Host "7. Validate Ticket"
        Write-Host "8. Logout"
        Write-Host "0. Back to Main Menu"
        
        $choice = Read-Host "`nEnter your choice"
        
        switch ($choice) {
            "1" { Register-User }
            "2" { Login-User }
            "3" { Show-Routes }
            "4" { Show-Trips }
            "5" { Purchase-Ticket }
            "6" { Show-MyTickets }
            "7" { Validate-Ticket }
            "8" { 
                $Global:CurrentUser = $null
                Write-Success "Logged out successfully"
                Start-Sleep -Seconds 1
            }
            "0" { return }
            default { 
                Write-Error "Invalid choice"
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Show-AdminMenu {
    while ($true) {
        Clear-Host
        Write-Title "ADMIN MENU"
        
        Write-Host "`n1. View Dashboard"
        Write-Host "2. View All Routes"
        Write-Host "3. View All Trips"
        Write-Host "4. Create Route"
        Write-Host "5. Create Trip"
        Write-Host "6. Update Trip Status"
        Write-Host "7. Sales Report"
        Write-Host "8. Traffic Report"
        Write-Host "0. Back to Main Menu"
        
        $choice = Read-Host "`nEnter your choice"
        
        switch ($choice) {
            "1" { Show-Dashboard }
            "2" { Show-Routes }
            "3" { Show-Trips }
            "4" { Create-Route }
            "5" { Create-Trip }
            "6" { Update-TripStatus }
            "7" { Show-SalesReport }
            "8" { Show-TrafficReport }
            "0" { return }
            default { 
                Write-Error "Invalid choice"
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  ╔════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "  ║                                            ║" -ForegroundColor Cyan
        Write-Host "  ║   TRANSPORT TICKETING SYSTEM               ║" -ForegroundColor Cyan
        Write-Host "  ║   Windhoek City Council                    ║" -ForegroundColor Cyan
        Write-Host "  ║                                            ║" -ForegroundColor Cyan
        Write-Host "  ╚════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "  1. Passenger Portal" -ForegroundColor White
        Write-Host "  2. Admin Portal" -ForegroundColor White
        Write-Host "  3. Validator Portal" -ForegroundColor White
        Write-Host "  0. Exit" -ForegroundColor White
        Write-Host ""
        
        $choice = Read-Host "  Select an option"
        
        switch ($choice) {
            "1" { Show-PassengerMenu }
            "2" { Show-AdminMenu }
            "3" { Validate-Ticket }
            "0" { 
                Write-Host "`n  Thank you for using the Transport Ticketing System!" -ForegroundColor Cyan
                Write-Host ""
                exit 
            }
            default { 
                Write-Error "Invalid choice"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Main execution
Clear-Host
Write-Title "TRANSPORT TICKETING SYSTEM"
Write-Host "Checking if services are running..." -ForegroundColor Yellow

if (Test-ServicesRunning) {
    Write-Success "All services are operational!"
    Start-Sleep -Seconds 2
    Show-MainMenu
} else {
    Write-Host "`nPlease start the services first:" -ForegroundColor Yellow
    Write-Host "  docker-compose up -d" -ForegroundColor White
    Write-Host ""
}