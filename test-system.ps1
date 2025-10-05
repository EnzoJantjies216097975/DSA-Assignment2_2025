# Smart Transport System - Windows Testing Script
# Run this from PowerShell after starting the system
# To run: .\test-system.ps1

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Smart Transport System - Test Suite" -ForegroundColor Cyan
Write-Host "Windows Testing Environment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Initialize test counters
$global:TestsPassed = 0
$global:TestsFailed = 0
$global:TestsSkipped = 0

# Base URL for services
$BaseURL = "http://localhost"

# Function to test an HTTP endpoint
function Test-Endpoint {
    param(
        [string]$ServiceName,
        [int]$Port,
        [string]$Endpoint,
        [int]$ExpectedCode = 200,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body = $null
    )
    
    $url = "${BaseURL}:${Port}${Endpoint}"
    Write-Host -NoNewline "Testing $ServiceName $Endpoint... "
    
    try {
        $params = @{
            Uri = $url
            Method = $Method
            Headers = $Headers
            TimeoutSec = 10
            ErrorAction = "Stop"
        }
        
        if ($Body) {
            $params.Body = $Body
            $params.ContentType = "application/json"
        }
        
        $response = Invoke-WebRequest @params
        
        if ($response.StatusCode -eq $ExpectedCode) {
            Write-Host "✅ PASSED" -ForegroundColor Green -NoNewline
            Write-Host " (HTTP $($response.StatusCode))" -ForegroundColor Gray
            $global:TestsPassed++
            return $response.Content
        } else {
            Write-Host "❌ FAILED" -ForegroundColor Red -NoNewline
            Write-Host " (Expected $ExpectedCode, got $($response.StatusCode))" -ForegroundColor Gray
            $global:TestsFailed++
            return $null
        }
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq $ExpectedCode) {
            Write-Host "✅ PASSED" -ForegroundColor Green -NoNewline
            Write-Host " (HTTP $ExpectedCode as expected)" -ForegroundColor Gray
            $global:TestsPassed++
            return $true
        } else {
            Write-Host "❌ FAILED" -ForegroundColor Red -NoNewline
            Write-Host " (Error: $($_.Exception.Message))" -ForegroundColor Gray
            $global:TestsFailed++
            return $null
        }
    }
}

# Function to test MongoDB connection
function Test-MongoDB {
    Write-Host -NoNewline "Testing MongoDB connection... "
    try {
        $result = docker exec mongodb mongosh --quiet transport_db --eval "db.getName()" 2>$null
        if ($result -match "transport_db") {
            Write-Host "✅ PASSED" -ForegroundColor Green
            $global:TestsPassed++
            return $true
        } else {
            Write-Host "❌ FAILED" -ForegroundColor Red
            $global:TestsFailed++
            return $false
        }
    } catch {
        Write-Host "❌ FAILED" -ForegroundColor Red -NoNewline
        Write-Host " (Error: $_)" -ForegroundColor Gray
        $global:TestsFailed++
        return $false
    }
}

# Function to test Kafka connection
function Test-Kafka {
    Write-Host -NoNewline "Testing Kafka connection... "
    try {
        $topics = docker exec kafka kafka-topics.sh --list --bootstrap-server localhost:9092 2>$null
        if ($topics) {
            Write-Host "✅ PASSED" -ForegroundColor Green
            $global:TestsPassed++
            return $true
        } else {
            Write-Host "❌ FAILED" -ForegroundColor Red
            $global:TestsFailed++
            return $false
        }
    } catch {
        Write-Host "❌ FAILED" -ForegroundColor Red -NoNewline
        Write-Host " (Error: $_)" -ForegroundColor Gray
        $global:TestsFailed++
        return $false
    }
}

# ====================
# Run Tests
# ====================

Write-Host "1. Infrastructure Services" -ForegroundColor Yellow
Write-Host "-------------------------" -ForegroundColor Gray
Test-MongoDB
Test-Kafka
Write-Host ""

Write-Host "2. Service Health Endpoints" -ForegroundColor Yellow
Write-Host "--------------------------" -ForegroundColor Gray

# Note: Some services might not have health endpoints, so we test their main endpoints
$services = @(
    @{Name="Passenger Service"; Port=8081; Endpoint="/passenger/health"; ExpectedCode=404},
    @{Name="Transport Service"; Port=8082; Endpoint="/transport/routes"; ExpectedCode=200},
    @{Name="Ticketing Service"; Port=8083; Endpoint="/ticketing/pricing"; ExpectedCode=200},
    @{Name="Payment Service"; Port=8084; Endpoint="/payment/statistics"; ExpectedCode=200},
    @{Name="Admin Service"; Port=9090; Endpoint="/health"; ExpectedCode=200}
)

foreach ($service in $services) {
    Test-Endpoint -ServiceName $service.Name -Port $service.Port -Endpoint $service.Endpoint -ExpectedCode $service.ExpectedCode | Out-Null
}

Write-Host ""

Write-Host "3. User Registration & Login Flow" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Gray

# Generate unique test user
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$testUser = "testuser_$timestamp"
$testEmail = "test_$timestamp@windhoek.com"

$registerData = @{
    username = $testUser
    email = $testEmail
    password = "TestPass123!"
    fullName = "Test User"
    phoneNumber = "+264812345678"
} | ConvertTo-Json

Write-Host "Creating user: $testUser" -ForegroundColor Cyan
$registerResponse = Test-Endpoint -ServiceName "Passenger" -Port 8081 -Endpoint "/passenger/register" `
    -Method "POST" -Body $registerData

# Extract token if registration successful
$token = $null
if ($registerResponse) {
    try {
        $responseObj = $registerResponse | ConvertFrom-Json
        $token = $responseObj.token
        if ($token) {
            Write-Host "Token received: $($token.Substring(0, [Math]::Min(20, $token.Length)))..." -ForegroundColor Cyan
        }
    } catch {
        Write-Host "Could not extract token from response" -ForegroundColor Yellow
    }
}

# Test login
$loginData = @{
    username = $testUser
    password = "TestPass123!"
} | ConvertTo-Json

Test-Endpoint -ServiceName "Passenger" -Port 8081 -Endpoint "/passenger/login" `
    -Method "POST" -Body $loginData | Out-Null

Write-Host ""

Write-Host "4. Route & Trip Management" -ForegroundColor Yellow
Write-Host "------------------------" -ForegroundColor Gray

# Create a test route
$routeData = @{
    routeName = "Test Route CBD to Katutura"
    transportType = "BUS"
    startPoint = "CBD Terminal"
    endPoint = "Katutura Station"
    intermediateStops = @(
        @{
            stopId = "STOP-001"
            stopName = "Independence Avenue"
            arrivalTime = "08:15"
            departureTime = "08:17"
        }
    )
    isActive = $true
} | ConvertTo-Json -Depth 3

$routeResponse = Test-Endpoint -ServiceName "Transport" -Port 8082 -Endpoint "/transport/routes" `
    -Method "POST" -Body $routeData

$routeId = $null
if ($routeResponse) {
    try {
        $routeObj = $routeResponse | ConvertFrom-Json
        $routeId = $routeObj.routeId
        Write-Host "Route created with ID: $routeId" -ForegroundColor Cyan
    } catch {
        Write-Host "Could not extract route ID" -ForegroundColor Yellow
    }
}

# Create a test trip
$departureTime = (Get-Date).AddDays(1).ToString("yyyy-MM-ddTHH:mm:ssZ")
$arrivalTime = (Get-Date).AddDays(1).AddHours(2).ToString("yyyy-MM-ddTHH:mm:ssZ")

$tripData = @{
    routeId = if ($routeId) { $routeId } else { "BUS-001" }
    scheduledDepartureTime = $departureTime
    scheduledArrivalTime = $arrivalTime
    vehicleId = "BUS-WDH-001"
    driverInfo = @{
        driverId = "DRV-001"
        driverName = "John Namibia"
    }
    capacity = 50
} | ConvertTo-Json -Depth 3

$tripResponse = Test-Endpoint -ServiceName "Transport" -Port 8082 -Endpoint "/transport/trips" `
    -Method "POST" -Body $tripData

Write-Host ""

Write-Host "5. Ticketing System" -ForegroundColor Yellow
Write-Host "-----------------" -ForegroundColor Gray

# Create a test ticket
$ticketData = @{
    userId = "USER-TEST-001"
    ticketType = "SINGLE"
    paymentMethod = "CARD"
    tripDetails = @{
        tripId = "TRIP-001"
        routeId = if ($routeId) { $routeId } else { "BUS-001" }
        boardingStop = "CBD Terminal"
        destinationStop = "Katutura Station"
    }
} | ConvertTo-Json -Depth 3

$headers = @{}
if ($token) {
    $headers["Authorization"] = "Bearer $token"
}

$ticketResponse = Test-Endpoint -ServiceName "Ticketing" -Port 8083 -Endpoint "/ticketing/tickets" `
    -Method "POST" -Body $ticketData -Headers $headers

$ticketId = $null
if ($ticketResponse) {
    try {
        $ticketObj = $ticketResponse | ConvertFrom-Json
        $ticketId = $ticketObj.ticketId
        Write-Host "Ticket created with ID: $ticketId" -ForegroundColor Cyan
    } catch {
        Write-Host "Could not extract ticket ID" -ForegroundColor Yellow
    }
}

Write-Host ""

Write-Host "6. Database Collections Check" -ForegroundColor Yellow
Write-Host "---------------------------" -ForegroundColor Gray

try {
    $collections = docker exec mongodb mongosh --quiet transport_db --eval "db.getCollectionNames()" 2>$null
    $requiredCollections = @("users", "routes", "trips", "tickets", "payments", "notifications")
    
    foreach ($collection in $requiredCollections) {
        Write-Host -NoNewline "Checking collection '$collection'... "
        if ($collections -match $collection) {
            Write-Host "✅ EXISTS" -ForegroundColor Green
            $global:TestsPassed++
        } else {
            Write-Host "❌ MISSING" -ForegroundColor Red
            $global:TestsFailed++
        }
    }
} catch {
    Write-Host "Could not verify MongoDB collections" -ForegroundColor Yellow
    $global:TestsSkipped += 6
}

Write-Host ""

Write-Host "7. Kafka Topics Check" -ForegroundColor Yellow
Write-Host "-------------------" -ForegroundColor Gray

try {
    $topics = docker exec kafka kafka-topics.sh --list --bootstrap-server localhost:9092 2>$null
    $requiredTopics = @("ticket.requests", "payments.processed", "ticket.validations", "passenger.registrations")
    
    foreach ($topic in $requiredTopics) {
        Write-Host -NoNewline "Checking topic '$topic'... "
        if ($topics -match $topic) {
            Write-Host "✅ EXISTS" -ForegroundColor Green
            $global:TestsPassed++
        } else {
            Write-Host "❌ MISSING" -ForegroundColor Red
            $global:TestsFailed++
        }
    }
} catch {
    Write-Host "Could not verify Kafka topics" -ForegroundColor Yellow
    $global:TestsSkipped += 4
}

Write-Host ""

Write-Host "8. Container Status Check" -ForegroundColor Yellow
Write-Host "-----------------------" -ForegroundColor Gray

$containers = @("mongodb", "kafka", "zookeeper", "passenger-service", "transport-service", 
                "ticketing-service", "payment-service", "admin-service", "kafka-ui")

foreach ($container in $containers) {
    Write-Host -NoNewline "Checking container '$container'... "
    try {
        $status = docker inspect $container --format '{{.State.Status}}' 2>$null
        if ($status -eq "running") {
            Write-Host "✅ RUNNING" -ForegroundColor Green
            $global:TestsPassed++
        } else {
            Write-Host "⚠️ $status" -ForegroundColor Yellow
            $global:TestsFailed++
        }
    } catch {
        Write-Host "❌ NOT FOUND" -ForegroundColor Red
        $global:TestsFailed++
    }
}

Write-Host ""

# Final Summary
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Test Results Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Tests Passed: $global:TestsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $global:TestsFailed" -ForegroundColor $(if ($global:TestsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "Tests Skipped: $global:TestsSkipped" -ForegroundColor Yellow

$totalTests = $global:TestsPassed + $global:TestsFailed
if ($totalTests -gt 0) {
    $successRate = [Math]::Round(($global:TestsPassed / $totalTests) * 100, 2)
    Write-Host "Success Rate: $successRate%" -ForegroundColor $(
        if ($successRate -ge 80) { "Green" }
        elseif ($successRate -ge 60) { "Yellow" }
        else { "Red" }
    )
    
    Write-Host ""
    if ($successRate -ge 80) {
        Write-Host "✅ System is ready for submission!" -ForegroundColor Green
    } elseif ($successRate -ge 60) {
        Write-Host "⚠️ System mostly working but needs attention" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Critical issues detected - fix before submission" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Additional Manual Tests Recommended:" -ForegroundColor Yellow
Write-Host "1. Open Kafka UI at http://localhost:8090 to verify message flow" -ForegroundColor White
Write-Host "2. Connect to MongoDB with a client to verify data persistence" -ForegroundColor White
Write-Host "3. Test the CLI client with: docker exec -it cli-client bal run" -ForegroundColor White
Write-Host "4. Check service logs for errors: docker logs [service-name]" -ForegroundColor White
Write-Host ""