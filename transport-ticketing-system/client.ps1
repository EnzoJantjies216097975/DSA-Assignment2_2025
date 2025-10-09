# Transport Ticketing System Client


# Global variables to store session data
$Global:CurrentUser = $null
$Global:IsAdmin = $false

# Get MongoDB container name dynamically
function Get-MongoContainerName {
    try {
        $containers = docker ps --format "{{.Names}}" | Select-String -Pattern "mongodb|mongo"
        if ($containers) {
            return $containers[0].ToString()
        }
        # Try common naming patterns
        $patterns = @("mongodb", "mongo", "mongodb-1", "mongo-1")
        foreach ($pattern in $patterns) {
            $result = docker ps --filter "name=$pattern" --format "{{.Names}}" 2>$null
            if ($result) {
                return $result
            }
        }
        return $null
    } catch {
        return $null
    }
}

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

function Write-Warning {
    param([string]$Text)
    Write-Host "[WARNING] $Text" -ForegroundColor Magenta
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

# ============================================
# AUTHENTICATION FUNCTIONS
# ============================================

function Login-Admin {
    Write-Title "ADMIN LOGIN"
    
    $username = Read-Host "Enter admin username"
    $password = Read-Host "Enter admin password" -AsSecureString
    $passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    
    try {
        $body = @{
            email = $username
            password = $passwordPlain
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "http://localhost:9090/passenger/login" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body `
            -ErrorAction Stop
        
        # Fetch full user profile to get role
        $profile = Invoke-RestMethod -Uri "http://localhost:9090/passenger/profile/$($response.userId)" -Method Get -ErrorAction Stop
        
        # Check if user is actually an admin
        if ($profile.role -ne "ADMIN") {
            Write-Error "Access Denied: This account does not have administrator privileges"
            Write-Warning "Please login as Passenger instead"
            Read-Host "`nPress Enter to continue"
            return $false
        }
        
        $Global:CurrentUser = @{
            UserId = $response.userId
            Email = $response.email
            FirstName = $response.firstName
            LastName = $response.lastName
            Role = $profile.role
        }
        
        $Global:IsAdmin = $true
        
        Write-Success "Admin login successful!"
        Write-Host "Welcome, Administrator $($response.firstName) $($response.lastName)!" -ForegroundColor Magenta
        Start-Sleep -Seconds 2
        return $true
        
    } catch {
        Write-Error "Login failed: Invalid username or password"
        Read-Host "`nPress Enter to continue"
        return $false
    }
}

function Login-Passenger {
    Write-Title "PASSENGER LOGIN"
    
    $username = Read-Host "Enter username"
    $password = Read-Host "Enter password" -AsSecureString
    $passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    
    try {
        $body = @{
            email = $username
            password = $passwordPlain
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "http://localhost:9090/passenger/login" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body `
            -ErrorAction Stop
        
        # Fetch full user profile to get role
        $profile = Invoke-RestMethod -Uri "http://localhost:9090/passenger/profile/$($response.userId)" -Method Get -ErrorAction Stop
        
        # Check if user is an admin trying to login as passenger
        if ($profile.role -eq "ADMIN") {
            Write-Warning "This is an administrator account"
            Write-Info "Please login through Admin portal instead"
            Read-Host "`nPress Enter to continue"
            return $false
        }
        
        $Global:CurrentUser = @{
            UserId = $response.userId
            Email = $response.email
            FirstName = $response.firstName
            LastName = $response.lastName
            Role = $profile.role
        }
        
        $Global:IsAdmin = $false
        
        Write-Success "Login successful!"
        Write-Host "Welcome, $($response.firstName) $($response.lastName)!" -ForegroundColor Cyan
        Start-Sleep -Seconds 2
        return $true
        
    } catch {
        Write-Error "Login failed: Invalid username or password"
        Read-Host "`nPress Enter to continue"
        return $false
    }
}

function Register-Passenger {
    Write-Title "PASSENGER REGISTRATION"
    
    $email = Read-Host "Enter email/username"
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
        Write-Host "Username: $($response.email)" -ForegroundColor Gray
        Write-Host ""
        Write-Info "You can now login with your credentials"
        
    } catch {
        Write-Error "Registration failed: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

# ============================================
# ADMIN FUNCTIONS
# ============================================

function Show-AdminDashboard {
    Clear-Host
    Write-Title "ADMINISTRATOR DASHBOARD"
    
    Write-Host "Logged in as: $($Global:CurrentUser.FirstName) $($Global:CurrentUser.LastName)" -ForegroundColor Magenta
    Write-Host "Username: $($Global:CurrentUser.Email)" -ForegroundColor Gray
    Write-Host "Role: ADMINISTRATOR" -ForegroundColor Magenta
    
    # Fetch dashboard stats
    try {
        $dashboard = Invoke-RestMethod -Uri "http://localhost:9095/admin/dashboard" -Method Get -ErrorAction SilentlyContinue
        
        Write-Host ""
        Write-Host "=== SYSTEM OVERVIEW ===" -ForegroundColor Cyan
        Write-Host "Total Routes:  $($dashboard.totalRoutes)" -ForegroundColor White
        Write-Host "Total Trips:   $($dashboard.totalTrips)" -ForegroundColor White
        Write-Host "Total Tickets: $($dashboard.totalTickets)" -ForegroundColor White
        Write-Host "Total Revenue: N`$$($dashboard.totalRevenue)" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "=== SYSTEM OVERVIEW ===" -ForegroundColor Cyan
        Write-Host "Dashboard statistics unavailable" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "=== USER MANAGEMENT ===" -ForegroundColor Cyan
    Write-Host "1. Register New User (Passenger/Admin)" -ForegroundColor White
    Write-Host "2. List All Users" -ForegroundColor White
    Write-Host "3. Promote User to Admin" -ForegroundColor White
    
    Write-Host ""
    Write-Host "=== ROUTE MANAGEMENT ===" -ForegroundColor Cyan
    Write-Host "4. View All Routes" -ForegroundColor White
    Write-Host "5. Create New Route" -ForegroundColor White
    
    Write-Host ""
    Write-Host "=== TRIP MANAGEMENT ===" -ForegroundColor Cyan
    Write-Host "6. View All Trips" -ForegroundColor White
    Write-Host "7. Schedule New Trip" -ForegroundColor White
    Write-Host "8. Update Trip Status" -ForegroundColor White
    
    Write-Host ""
    Write-Host "=== REPORTS ===" -ForegroundColor Cyan
    Write-Host "9. Sales Report" -ForegroundColor White
    Write-Host "10. Traffic Report" -ForegroundColor White
    
    Write-Host ""
    Write-Host "0. Logout" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "Enter your choice"
    
    switch ($choice) {
        "1" { Register-UserByAdmin }
        "2" { List-AllUsers }
        "3" { Promote-UserToAdmin }
        "4" { Show-Routes }
        "5" { Create-Route }
        "6" { Show-Trips }
        "7" { Create-Trip }
        "8" { Update-TripStatus }
        "9" { Show-SalesReport }
        "10" { Show-TrafficReport }
        "0" { 
            $Global:CurrentUser = $null
            $Global:IsAdmin = $false
            Write-Success "Logged out successfully"
            Start-Sleep -Seconds 1
            return $false
        }
        default { 
            Write-Error "Invalid choice"
            Start-Sleep -Seconds 1
        }
    }
    
    return $true
}

function Register-UserByAdmin {
    Write-Title "REGISTER NEW USER (ADMIN)"
    
    $email = Read-Host "Enter email/username"
    $password = Read-Host "Enter password" -AsSecureString
    $passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    $firstName = Read-Host "Enter first name"
    $lastName = Read-Host "Enter last name"
    $phone = Read-Host "Enter phone number"
    
    Write-Host ""
    Write-Host "Select Role:" -ForegroundColor Yellow
    Write-Host "1. PASSENGER (default)"
    Write-Host "2. ADMIN"
    $roleChoice = Read-Host "Enter choice (1-2)"
    $role = if ($roleChoice -eq "2") { "ADMIN" } else { "PASSENGER" }
    
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
        
        # If admin role selected, update it
        if ($role -eq "ADMIN") {
            $mongoContainer = Get-MongoContainerName
            if ($mongoContainer) {
                $mongoCommand = "use transport_db; db.users.updateOne({email: `"$email`"}, {`$set: {role: `"ADMIN`"}})"
                docker exec -i $mongoContainer mongosh -u admin -p password123 --quiet --eval $mongoCommand | Out-Null
            } else {
                Write-Warning "Could not find MongoDB container. User created as PASSENGER."
                Write-Info "Run .\make-admin.ps1 to promote user manually"
                $role = "PASSENGER"
            }
        }
        
        Write-Success "User registered successfully!"
        Write-Host "User ID: $($response.userId)" -ForegroundColor Gray
        Write-Host "Username: $($response.email)" -ForegroundColor Gray
        Write-Host "Role: $role" -ForegroundColor $(if($role -eq "ADMIN"){"Magenta"}else{"Green"})
        
    } catch {
        Write-Error "Registration failed: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function List-AllUsers {
    Write-Title "ALL REGISTERED USERS"
    
    try {
        $mongoContainer = Get-MongoContainerName
        
        if (-not $mongoContainer) {
            Write-Error "MongoDB container not found"
            Write-Info "Available containers:"
            docker ps --format "{{.Names}}" | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
        } else {
            $mongoCommand = 'use transport_db; db.users.find({}, {email: 1, firstName: 1, lastName: 1, role: 1, phone: 1, _id: 0}).sort({createdAt: -1})'
            $result = docker exec -i $mongoContainer mongosh -u admin -p password123 --quiet --eval $mongoCommand 2>&1
            
            Write-Host $result
        }
        
    } catch {
        Write-Error "Failed to fetch users: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Promote-UserToAdmin {
    Write-Title "PROMOTE USER TO ADMIN"
    
    $email = Read-Host "Enter user username/email to promote"
    
    try {
        $mongoContainer = Get-MongoContainerName
        
        if (-not $mongoContainer) {
            Write-Error "MongoDB container not found"
            Write-Info "Run: .\make-admin.ps1 instead"
        } else {
            $mongoCommand = "use transport_db; var result = db.users.updateOne({email: `"$email`"}, {`$set: {role: `"ADMIN`"}}); if (result.matchedCount === 0) { print('ERROR: User not found'); } else { print('SUCCESS: User promoted to ADMIN'); }"
            $result = docker exec -i $mongoContainer mongosh -u admin -p password123 --quiet --eval $mongoCommand 2>&1
            
            if ($result -match "SUCCESS") {
                Write-Success "User promoted to ADMIN successfully!"
            } else {
                Write-Error "User not found with username: $email"
            }
        }
        
    } catch {
        Write-Error "Failed to promote user: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Create-Route {
    Write-Title "CREATE NEW ROUTE"
    
    $routeNumber = Read-Host "Enter route number (e.g., R101)"
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
        
        Write-Success "Route created successfully!"
        Write-Host "Route ID: $($response.routeId)" -ForegroundColor Cyan
        
    } catch {
        Write-Error "Failed to create route: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Create-Trip {
    Write-Title "SCHEDULE NEW TRIP"
    
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
        
        Write-Success "Trip scheduled successfully!"
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
        Write-Info "Notifications sent to affected passengers"
        
    } catch {
        Write-Error "Failed to update trip: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-SalesReport {
    Write-Title "SALES REPORT"
    
    try {
        $report = Invoke-RestMethod -Uri "http://localhost:9095/admin/reports/sales" -Method Get
        
        Write-Host "`nSales Summary:" -ForegroundColor Cyan
        Write-Host "Total Tickets Sold: $($report.totalTicketsSold)" -ForegroundColor White
        Write-Host "Total Revenue: N`$$($report.totalRevenue)" -ForegroundColor Green
        
        Write-Host "`nBreakdown by Ticket Type:" -ForegroundColor Cyan
        foreach ($type in $report.ticketsByType.PSObject.Properties) {
            $revenue = $report.revenueByType.($type.Name)
            Write-Host "  $($type.Name): $($type.Value) tickets (N`$$revenue)" -ForegroundColor White
        }
        
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
        Write-Host "Total Passengers: $($report.totalPassengers)" -ForegroundColor White
        
        Write-Host "`nPassengers by Route:" -ForegroundColor Cyan
        foreach ($route in $report.passengersByRoute.PSObject.Properties) {
            Write-Host "  Route $($route.Name): $($route.Value) passengers" -ForegroundColor White
        }
        
    } catch {
        Write-Error "Failed to generate report: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

# ============================================
# PASSENGER FUNCTIONS
# ============================================

function Show-PassengerDashboard {
    Clear-Host
    Write-Title "PASSENGER DASHBOARD"
    
    Write-Host "Logged in as: $($Global:CurrentUser.FirstName) $($Global:CurrentUser.LastName)" -ForegroundColor Green
    Write-Host "Username: $($Global:CurrentUser.Email)" -ForegroundColor Gray
    
    # Show quick stats
    try {
        $tickets = Invoke-RestMethod -Uri "http://localhost:9092/ticketing/users/$($Global:CurrentUser.UserId)/tickets" -Method Get -ErrorAction SilentlyContinue
        $activeTickets = ($tickets | Where-Object { $_.status -eq "PAID" }).Count
        
        Write-Host ""
        Write-Host "=== MY ACCOUNT ===" -ForegroundColor Cyan
        Write-Host "Total Tickets: $($tickets.Count)" -ForegroundColor White
        Write-Host "Active Tickets: $activeTickets" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "=== MY ACCOUNT ===" -ForegroundColor Cyan
        Write-Host "Loading tickets..." -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "=== BROWSE ===" -ForegroundColor Cyan
    Write-Host "1. View All Routes" -ForegroundColor White
    Write-Host "2. View Available Trips" -ForegroundColor White
    
    Write-Host ""
    Write-Host "=== MY TICKETS ===" -ForegroundColor Cyan
    Write-Host "3. Purchase Ticket" -ForegroundColor White
    Write-Host "4. View My Tickets" -ForegroundColor White
    Write-Host "5. Validate Ticket" -ForegroundColor White
    
    Write-Host ""
    Write-Host "0. Logout" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "Enter your choice"
    
    switch ($choice) {
        "1" { Show-Routes }
        "2" { Show-Trips }
        "3" { Purchase-Ticket }
        "4" { Show-MyTickets }
        "5" { Validate-Ticket }
        "0" { 
            $Global:CurrentUser = $null
            $Global:IsAdmin = $false
            Write-Success "Logged out successfully"
            Start-Sleep -Seconds 1
            return $false
        }
        default { 
            Write-Error "Invalid choice"
            Start-Sleep -Seconds 1
        }
    }
    
    return $true
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
                Write-Host "  ID: $($route.id)" -ForegroundColor Gray
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
    Write-Title "PURCHASE TICKET"
    
    Write-Host "`nTicket Types:" -ForegroundColor Yellow
    Write-Host "1. SINGLE_RIDE (N`$15.00)"
    Write-Host "2. MULTIPLE_RIDE (N`$120.00 - 10 rides)"
    Write-Host "3. DAILY_PASS (N`$50.00)"
    Write-Host "4. WEEKLY_PASS (N`$300.00)"
    Write-Host "5. MONTHLY_PASS (N`$1000.00)"
    
    $choice = Read-Host "`nSelect ticket type (1-5)"
    
    if ([int]$choice -lt 1 -or [int]$choice -gt 5) {
        Write-Error "Invalid ticket type"
        Read-Host "Press Enter to continue"
        return
    }
    
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
        Write-Info "Payment is being processed automatically..."
        
    } catch {
        Write-Error "Purchase failed: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-MyTickets {
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

# ============================================
# MAIN MENU
# ============================================

function Show-LoginMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "                                              " -ForegroundColor Cyan
    Write-Host "    TRANSPORT TICKETING SYSTEM                " -ForegroundColor Cyan
    Write-Host "    Windhoek City Council                     " -ForegroundColor Cyan
    Write-Host "                                              " -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  === LOGIN AS ===" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Admin" -ForegroundColor Magenta
    Write-Host "  2. Passenger" -ForegroundColor Green
    Write-Host ""
    Write-Host "  === NEW USER ===" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  3. Register as Passenger" -ForegroundColor White
    Write-Host ""
    Write-Host "  0. Exit" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "  Select an option"
    
    switch ($choice) {
        "1" { 
            $loginSuccess = Login-Admin
            if ($loginSuccess) {
                while (Show-AdminDashboard) { }
            }
            # If login failed, loop back to main menu
        }
        "2" { 
            $loginSuccess = Login-Passenger
            if ($loginSuccess) {
                while (Show-PassengerDashboard) { }
            }
            # If login failed, loop back to main menu
        }
        "3" { 
            Register-Passenger
            # After registration, return to login menu
        }
        "0" { 
            Write-Host "`n  Thank you for using the Transport Ticketing System!" -ForegroundColor Cyan
            Write-Host ""
            exit 
        }
        default { 
            Write-Error "  Invalid choice"
            Start-Sleep -Seconds 1
        }
    }
}

# ============================================
# MAIN EXECUTION
# ============================================

Clear-Host
Write-Title "TRANSPORT TICKETING SYSTEM"
Write-Host "Checking if services are running..." -ForegroundColor Yellow

if (Test-ServicesRunning) {
    Write-Success "All services are operational!"
    Start-Sleep -Seconds 2
    
    # Main application loop
    while ($true) {
        Show-LoginMenu
    }
} else {
    Write-Host "`nPlease start the services first:" -ForegroundColor Yellow
    Write-Host "  docker-compose up -d" -ForegroundColor White
    Write-Host ""
}