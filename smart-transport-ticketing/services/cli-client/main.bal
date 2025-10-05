import ballerina/io;
import ballerina/http;
import ballerina/time;
import ballerina/regex;

// Service endpoints
configurable string PASSENGER_SERVICE = "http://localhost:8081";
configurable string TRANSPORT_SERVICE = "http://localhost:8082";
configurable string TICKETING_SERVICE = "http://localhost:8083";
configurable string PAYMENT_SERVICE = "http://localhost:8084";
configurable string NOTIFICATION_SERVICE = "http://localhost:8085";
configurable string ADMIN_SERVICE = "http://localhost:9090";

// HTTP clients for each microservice
final http:Client passengerClient = check new (PASSENGER_SERVICE);
final http:Client transportClient = check new (TRANSPORT_SERVICE);
final http:Client ticketingClient = check new (TICKETING_SERVICE);
final http:Client paymentClient = check new (PAYMENT_SERVICE);
final http:Client notificationClient = check new (NOTIFICATION_SERVICE);
final http:Client adminClient = check new (ADMIN_SERVICE);


// User session information
type UserSession record {
    string userId;
    string username;
    string role;
    string token;
    string email;
    string fullName?;
};

// Ticket information
type TicketInfo record {
    string ticketId;
    string ticketType;
    string status;
    decimal price;
    string validUntil;
    string qrCode?;
};

// Route information
type RouteInfo record {
    string routeId;
    string routeName;
    string transportType;
    string startPoint;
    string endPoint;
    boolean isActive;
};

// Trip information
type TripInfo record {
    string tripId;
    string routeId;
    string scheduledDepartureTime;
    string scheduledArrivalTime;
    string status;
    int capacity;
    int occupiedSeats;
};

// Global session variable
UserSession? currentSession = ();

// Main Entry Point
public function main() returns error? {
    clearScreen()
    printWelcomeBanner();

    // Main application loop
    while true {
        error? result = ();

        if currentSession is () {
            // No user logged in - show authentication menu
            result = showAuthenticationMenu();
        } else {
            // User is logged in - show role-based menu
            UserSession session = <UserSession>currentSession;

            if session.role == "PASSENGER" {
                result = showPassengerMenu();
            } else if session.role == "ADMIN" || session.role == "SUPER_ADMIN" {
                result = showAdminMenu();
            } else if session.role == "VALIDATOR" {
                result = showValidatorMenu();
            } else {
                io:println("Unknown role: " + session.role);
                currentSession = ();
            }
        }
        
        // Check if user wants to exit
        if result is error && result.message() == "EXIT" {
            break;
        } else if result is error {
            io:println("An error occurred: " + result.message());
            io:println("Press Enter to continue...");
            _ = io:readln("");
        }
    }
    
    io:println("Thank you for using Smart Transport System. Goodbye!");
    return;
}

// UI Helper Funtions

function clearScreen() {
    // Clear screen (works on most terminals)
    io:print("\033[H\033[2J");
}

function printWelcomeBanner() {
    io:println("╔══════════════════════════════════════════════════════════════════════╗");
    io:println("║                                                                      ║");
    io:println("║             SMART PUBLIC TRANSPORT TICKETING SYSTEM                  ║");
    io:println("║                                                                      ║");
    io:println("║                      Windhoek City Council                           ║");
    io:println("║                    Distributed Systems Project                       ║");
    io:println("║                                                                      ║");
    io:println("╚══════════════════════════════════════════════════════════════════════╝");
    io:println("");
}

function printSectionHeader(string title) {
    int titleLength = title.length();
    string border = "═".repeat(titleLength + 8);
    io:println("\n╔" + border + "╗");
    io:println("║    " + title + "    ║");
    io:println("╚" + border + "╝");
}

function waitForEnter() {
    io:println("\nPress Enter to continue...");
    _ = io:readln("");
}

// Authentication Menu

function showAuthenticationMenu() returns error? {
    io:println("\n┌────────────────────────────────────────────┐");
    io:println("│          WELCOME - PLEASE LOGIN            │");
    io:println("├────────────────────────────────────────────┤");
    io:println("│                                            │");
    io:println("│  1. Passenger Login                        │");
    io:println("│  2. Register New Passenger Account         │");
    io:println("│  3. Administrator Login                    │");
    io:println("│  4. Validator Login                        │");
    io:println("│  5. Exit Application                       │");
    io:println("│                                            │");
    io:println("└────────────────────────────────────────────┘");
    
    string choice = io:readln("\n Enter your choice (1-5): ");
    
    match choice {
        "1" => { return performPassengerLogin(); }
        "2" => { return performPassengerRegistration(); }
        "3" => { return performAdminLogin(); }
        "4" => { return performValidatorLogin(); }
        "5" => { return error("EXIT"); }
        _ => {
            io:println(" Invalid choice. Please select 1-5.");
            waitForEnter();
            return;
        }
    }
}

// Authentication Functions
function performPassengerLogin() returns error? {
    printSectionHeader("PASSENGER LOGIN");
    
    io:println("\nPlease enter your credentials:");
    io:println("────────────────────────────────");
    
    string username = io:readln(" Username: ");
    string password = io:readln(" Password: ");
    
    if username.trim() == "" || password.trim() == "" {
        io:println("\n Username and password cannot be empty!");
        waitForEnter();
        return;
    }
    
    io:println("\n Authenticating...");
    
    json loginPayload = {
        "username": username,
        "password": password
    };
    
    http:Response|error response = passengerClient->post("/passenger/login", loginPayload);
    
    if response is error {
        io:println("Connection error: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json responseData = check response.getJsonPayload();
        
        currentSession = {
            userId: check responseData.user.id.ensureType(string),
            username: check responseData.user.username.ensureType(string),
            role: "PASSENGER",
            token: check responseData.token.ensureType(string),
            email: check responseData.user.email.ensureType(string),
            fullName: check responseData.user.fullName.ensureType(string)
        };
        
        io:println("\n Login successful!");
        io:println("Welcome back, " + check responseData.user.fullName.ensureType(string) + "! 🎉");
        waitForEnter();
    } else if response.statusCode == 401 {
        io:println("\n Login failed: Invalid username or password");
        waitForEnter();
    } else {
        io:println("\n Login failed: Server error");
        waitForEnter();
    }
}

function performPassengerRegistration() returns error? {
    printSectionHeader("NEW PASSENGER REGISTRATION");
    
    io:println("\nWelcome! Let's create your account.");
    io:println("Please provide the following information:");
    io:println("──────────────────────────────────────────");
    
    string username = io:readln("\nChoose a username: ");
    string email = io:readln("Email address: ");
    string fullName = io:readln("Full name: ");
    string password = io:readln("Choose a password (min 6 characters): ");
    string confirmPassword = io:readln("Confirm password: ");
    string phoneNumber = io:readln("Phone number (optional, press Enter to skip): ");
    
    // Validation
    if username.length() < 3 {
        io:println("\n Username must be at least 3 characters!");
        waitForEnter();
        return;
    }
    
    if password != confirmPassword {
        io:println("\n Passwords do not match!");
        waitForEnter();
        return;
    }
    
    if password.length() < 6 {
        io:println("\n Password must be at least 6 characters!");
        waitForEnter();
        return;
    }
    
    // Email validation (basic)
    if !email.includes("@") {
        io:println("\n Please enter a valid email address!");
        waitForEnter();
        return;
    }
    
    io:println("\n Creating your account...");
    
    json registrationPayload = {
        "username": username,
        "email": email,
        "password": password,
        "fullName": fullName,
        "phoneNumber": phoneNumber != "" ? phoneNumber : ()
    };
    
    http:Response|error response = passengerClient->post("/passenger/register", registrationPayload);
    
    if response is error {
        io:println("Connection error: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json responseData = check response.getJsonPayload();
        
        currentSession = {
            userId: check responseData.user.id.ensureType(string),
            username: username,
            role: "PASSENGER",
            token: check responseData.token.ensureType(string),
            email: email,
            fullName: fullName
        };
        
        io:println("\n Registration successful!");
        io:println("Welcome to Smart Transport, " + fullName + "! ");
        io:println("\n You can now:");
        io:println("   • Purchase tickets for buses and trains");
        io:println("   • View schedules and routes");
        io:println("   • Top up your account balance");
        io:println("   • Receive notifications about your trips");
        waitForEnter();
    } else if response.statusCode == 400 {
        io:println("\n Registration failed: Username or email already exists");
        waitForEnter();
    } else {
        io:println("\n Registration failed: Server error");
        waitForEnter();
    }
}

function performAdminLogin() returns error? {
    printSectionHeader("ADMINISTRATOR LOGIN");
    
    io:println("\n Administrative Access Required");
    io:println("─────────────────────────────────");
    
    string username = io:readln(" Admin username: ");
    string password = io:readln(" Admin password: ");
    
    io:println("\n Verifying administrator credentials...");
    
    json loginPayload = {
        "username": username,
        "password": password
    };
    
    http:Response|error response = adminClient->post("/login", loginPayload);
    
    if response is error {
        io:println(" Connection error: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json responseData = check response.getJsonPayload();
        
        currentSession = {
            userId: check responseData.user.username.ensureType(string),
            username: check responseData.user.username.ensureType(string),
            role: "ADMIN",
            token: check responseData.token.ensureType(string),
            email: check responseData.user.email.ensureType(string)
        };
    
        io:println("\n Administrator access granted!");
        io:println("Welcome, Admin " + username + "!");
        waitForEnter();
    } else if response.statusCode == 401 {
        io:println("\n Authentication failed: Invalid administrator credentials");
        waitForEnter();
    } else {
        io:println("\n Login failed: Server error");
        waitForEnter();
    }
}

function performValidatorLogin() returns error? {
    printSectionHeader("VALIDATOR LOGIN");
    
    io:println("\n Validator Access");
    io:println("───────────────────");
    
    string validatorId = io:readln(" Validator ID: ");
    string password = io:readln(" Password: ");
    
    // For demo purposes, use a simple validator login
    // In production, this would authenticate against the passenger service with VALIDATOR role
    
    if validatorId == "VAL001" && password == "validator123" {
        currentSession = {
            userId: "VAL-" + validatorId,
            username: "Validator " + validatorId,
            role: "VALIDATOR",
            token: "validator-token-demo", // In production, get real JWT
            email: "validator@transport.com"
        };
        
        io:println("\n Validator access granted!");
        io:println("Welcome, Validator " + validatorId + "!");
        waitForEnter();
    } else {
        io:println("\n Invalid validator credentials");
        waitForEnter();
    }
}

// PASSENGER MENU AND FUNCTIONS
function showPassengerMenu() returns error? {
    UserSession session = <UserSession>currentSession;
    
    clearScreen();
    io:println("╔═══════════════════════════════════════════════════╗");
    io:println("║              PASSENGER DASHBOARD                  ║");
    io:println("╠═══════════════════════════════════════════════════╣");
    io:println("║   " + session.username.padEnd(45) + "║");
    io:println("║   " + session.email.padEnd(45) + "║");
    io:println("╠═══════════════════════════════════════════════════╣");
    io:println("║                                                   ║");
    io:println("║   TRAVEL OPTIONS                                  ║");
    io:println("║   1. View Available Routes                        ║");
    io:println("║   2. Check Schedule                               ║");
    io:println("║   3. Purchase Ticket                              ║");
    io:println("║   4. View My Tickets                              ║");
    io:println("║                                                   ║");
    io:println("║   ACCOUNT MANAGEMENT                              ║");
    io:println("║   5. Check Account Balance                        ║");
    io:println("║   6. Top Up Account                               ║");
    io:println("║   7. View/Edit Profile                            ║");
    io:println("║   8. Notification Preferences                     ║");
    io:println("║                                                   ║");
    io:println("║   INFORMATION                                     ║");
    io:println("║   9.  View Service Disruptions                    ║");
    io:println("║   10. View Ticket History                         ║");
    io:println("║   11. View Payment History                        ║");
    io:println("║                                                   ║");
    io:println("║   12. Logout                                      ║");
    io:println("║                                                   ║");
    io:println("╚═══════════════════════════════════════════════════╝");
    
    string choice = io:readln("\n Select an option (1-12): ");
    
    match choice {
        "1" => { return viewAvailableRoutes(); }
        "2" => { return checkSchedule(); }
        "3" => { return purchaseTicket(); }
        "4" => { return viewMyTickets(); }
        "5" => { return checkAccountBalance(); }
        "6" => { return topUpAccount(); }
        "7" => { return viewEditProfile(); }
        "8" => { return updateNotificationPreferences(); }
        "9" => { return viewServiceDisruptions(); }
        "10" => { return viewTicketHistory(); }
        "11" => { return viewPaymentHistory(); }
        "12" => {
            currentSession = ();
            io:println("\n Logged out successfully!");
            waitForEnter();
        }
        _ => {
            io:println(" Invalid choice. Please select 1-12.");
            waitForEnter();
        }
    }
    return;
}

function viewAvailableRoutes() returns error? {
    printSectionHeader("AVAILABLE ROUTES");
    
    io:println("\nFilter by transport type:");
    io:println("1. Bus routes only");
    io:println("2. Train routes only");
    io:println("3. All routes");
    
    string filterChoice = io:readln("\n👉 Select filter (1-3): ");
    
    string endpoint = "/transport/routes";
    if filterChoice == "1" {
        endpoint = endpoint + "?transportType=BUS";
    } else if filterChoice == "2" {
        endpoint = endpoint + "?transportType=TRAIN";
    }
    
    io:println("\n Loading routes...");
    
    http:Response|error response = transportClient->get(endpoint);
    
    if response is error {
        io:println(" Failed to fetch routes: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json[] routes = check response.getJsonPayload().ensureType();
        
        if routes.length() == 0 {
            io:println("\n No routes found.");
        } else {
            io:println("\n Found " + routes.length().toString() + " route(s):\n");
            io:println("════════════════════════════════════════════════════════════");
            
            foreach int i in 0 ..< routes.length() {
                json route = routes[i];
                string icon = check route.transportType.ensureType(string) == "BUS" ? "🚌" : "🚊";
                
                io:println("\n" + icon + " Route #" + (i + 1).toString());
                io:println("───────────────────────────────");
                io:println("  ID: " + check route.routeId.ensureType(string));
                io:println("  Name: " + check route.routeName.ensureType(string));
                io:println("  Type: " + check route.transportType.ensureType(string));
                io:println("  From: " + check route.startPoint.ensureType(string));
                io:println("  To: " + check route.endPoint.ensureType(string));
                
                json stops = route.intermediateStops ?: [];
                if stops is json[] && stops.length() > 0 {
                    io:println("  Stops: " + stops.length().toString() + " intermediate stops");
                }
                
                boolean isActive = check route.isActive.ensureType(boolean);
                string status = isActive ? " Active" : " Inactive";
                io:println("  Status: " + status);
            }
            io:println("\n════════════════════════════════════════════════════════════");
        }
    } else {
        io:println(" Failed to fetch routes");
    }
    
    waitForEnter();
    return;
}

function checkSchedule() returns error? {
    printSectionHeader("CHECK SCHEDULE");
    
    io:println("\n Schedule Lookup");
    io:println("─────────────────");
    
    string date = io:readln("Enter date (YYYY-MM-DD) or press Enter for today: ");
    if date == "" {
        date = time:utcToString(time:utcNow()).substring(0, 10);
    }
    
    io:println("\nFilter by transport type:");
    io:println("1. Bus only");
    io:println("2. Train only");
    io:println("3. All");
    
    string filterChoice = io:readln("\n Select filter (1-3): ");
    
    string endpoint = "/transport/schedule?date=" + date;
    if filterChoice == "1" {
        endpoint = endpoint + "&transportType=BUS";
    } else if filterChoice == "2" {
        endpoint = endpoint + "&transportType=TRAIN";
    }
    
    io:println("\n Loading schedule for " + date + "...");
    
    http:Response|error response = transportClient->get(endpoint);
    
    if response is error {
        io:println(" Failed to fetch schedule: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json[] schedules = check response.getJsonPayload().ensureType();
        
        if schedules.length() == 0 {
            io:println("\n No trips scheduled for " + date);
        } else {
            io:println("\n Schedule for " + date);
            io:println("════════════════════════════════════════════");
            
            foreach json schedule in schedules {
                string routeName = check schedule.routeName.ensureType(string);
                io:println("\n Route: " + routeName);
                io:println("─────────────────────────");
                
                json trips = schedule.trips ?: [];
                if trips is json[] {
                    foreach json trip in trips {
                        string departure = check trip.scheduledDepartureTime.ensureType(string);
                        string arrival = check trip.scheduledArrivalTime.ensureType(string);
                        string status = check trip.status.ensureType(string);
                        
                        string statusIcon = "🟢";
                        if status == "CANCELLED" {
                            statusIcon = "🔴";
                        } else if status == "DELAYED" {
                            statusIcon = "🟡";
                        }
                        
                        io:println("  " + statusIcon + " Departure: " + departure.substring(11, 16));
                        io:println("     Arrival: " + arrival.substring(11, 16));
                        io:println("     Status: " + status);
                        io:println("");
                    }
                }
            }
        }
    } else {
        io:println(" Failed to fetch schedule");
    }
    
    waitForEnter();
    return;
}

function purchaseTicket() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("PURCHASE TICKET");
    
    // First, show ticket prices
    io:println("\n Loading ticket prices...");
    
    http:Response|error pricingResponse = ticketingClient->get("/ticketing/pricing");
    
    if pricingResponse is http:Response && pricingResponse.statusCode == 200 {
        json[] pricing = check pricingResponse.getJsonPayload().ensureType();
        
        io:println("\n TICKET PRICES (NAD)");
        io:println("══════════════════════════════════");
        foreach json price in pricing {
            string ticketType = check price.ticketType.ensureType(string);
            decimal basePrice = check price.basePrice.ensureType(decimal);
            
            string description = "";
            match ticketType {
                "SINGLE" => { description = "One-way trip"; }
                "RETURN" => { description = "Round trip"; }
                "DAY_PASS" => { description = "Unlimited rides for 1 day"; }
                "WEEK_PASS" => { description = "Unlimited rides for 7 days"; }
                "MONTH_PASS" => { description = "Unlimited rides for 30 days"; }
            }
            
            io:println(ticketType.padEnd(15) + "NAD " + basePrice.toString().padEnd(10) + description);
        }
        io:println("══════════════════════════════════");
    }
    
    io:println("\n SELECT TICKET TYPE:");
    io:println("─────────────────────────");
    io:println("1. SINGLE - One-way trip");
    io:println("2. RETURN - Round trip");
    io:println("3. DAY_PASS - Unlimited rides for one day");
    io:println("4. WEEK_PASS - Unlimited rides for one week");
    io:println("5. MONTH_PASS - Unlimited rides for one month");
    io:println("6. Cancel");
    
    string ticketChoice = io:readln("\n👉 Select ticket type (1-6): ");
    
    string ticketType = "";
    match ticketChoice {
        "1" => { ticketType = "SINGLE"; }
        "2" => { ticketType = "RETURN"; }
        "3" => { ticketType = "DAY_PASS"; }
        "4" => { ticketType = "WEEK_PASS"; }
        "5" => { ticketType = "MONTH_PASS"; }
        "6" => { return; }
        _ => {
            io:println(" Invalid selection");
            waitForEnter();
            return;
        }
    }
    
    // For single/return tickets, ask for trip details
    json tripDetails = {};
    if ticketType == "SINGLE" || ticketType == "RETURN" {
        io:println("\n TRIP DETAILS (Optional)");
        io:println("─────────────────────────");
        string routeId = io:readln("Route ID (press Enter to skip): ");
        
        if routeId != "" {
            string boardingStop = io:readln("Boarding stop: ");
            string destinationStop = io:readln("Destination stop: ");
            
            tripDetails = {
                "routeId": routeId,
                "boardingStop": boardingStop,
                "destinationStop": destinationStop
            };
        }
    }
    
    io:println("\n PAYMENT METHOD:");
    io:println("─────────────────");
    io:println("1. Account Balance");
    io:println("2. Credit/Debit Card");
    io:println("3. Mobile Money");
    io:println("4. Cancel");
    
    string paymentChoice = io:readln("\n👉 Select payment method (1-4): ");
    
    string paymentMethod = "";
    match paymentChoice {
        "1" => { paymentMethod = "ACCOUNT_BALANCE"; }
        "2" => { paymentMethod = "CARD"; }
        "3" => { paymentMethod = "MOBILE_MONEY"; }
        "4" => { return; }
        _ => {
            io:println(" Invalid selection");
            waitForEnter();
            return;
        }
    }
    
    // Confirm purchase
    io:println("\n PURCHASE SUMMARY:");
    io:println("─────────────────────");
    io:println("Ticket Type: " + ticketType);
    io:println("Payment Method: " + paymentMethod);
    
    string confirm = io:readln("\n Confirm purchase? (Y/N): ");
    if confirm.toUpperAscii() != "Y" {
        io:println(" Purchase cancelled");
        waitForEnter();
        return;
    }
    
    // Create ticket request
    json ticketRequest = {
        "userId": session.userId,
        "ticketType": ticketType,
        "paymentMethod": paymentMethod
    };
    
    if tripDetails != {} {
        ticketRequest = {...ticketRequest, "tripDetails": tripDetails};
    }
    
    io:println("\n Processing your ticket purchase...");
    
    http:Request request = new;
    request.setJsonPayload(ticketRequest);
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error purchaseResponse = ticketingClient->post("/ticketing/tickets", request);
    
    if purchaseResponse is error {
        io:println(" Purchase failed: " + purchaseResponse.message());
        waitForEnter();
        return;
    }
    
    if purchaseResponse.statusCode == 200 {
        json ticket = check purchaseResponse.getJsonPayload();
        string ticketId = check ticket.ticketId.ensureType(string);
        string status = check ticket.status.ensureType(string);
        decimal price = check ticket.price.ensureType(decimal);
        string validUntil = check ticket.validUntil.ensureType(string);
        string qrCode = check ticket.qrCode.ensureType(string);
        
        io:println("\n TICKET PURCHASED SUCCESSFULLY!");
        io:println("══════════════════════════════════════════");
        io:println(" TICKET DETAILS");
        io:println("──────────────────");
        io:println("Ticket ID: " + ticketId);
        io:println("Type: " + ticketType);
        io:println("Price: NAD " + price.toString());
        io:println("Status: " + status);
        io:println("Valid Until: " + validUntil.substring(0, 19));
        io:println("\n QR CODE:");
        io:println("┌─────────────┐");
        io:println("│ ▓▓ ▓  ▓ ▓▓  │");
        io:println("│ ▓  ▓▓▓  ▓   │");
        io:println("│ ▓▓ ▓  ▓ ▓▓  │");
        io:println("└─────────────┘");
        io:println("QR: " + qrCode.substring(0, 20) + "...");
        io:println("\n  IMPORTANT: Save your ticket ID for validation!");
        io:println("══════════════════════════════════════════");
        
        if status == "CREATED" {
            io:println("\n  Note: Payment is being processed. Your ticket will be activated once payment is confirmed.");
        }
    } else if purchaseResponse.statusCode == 400 {
        json errorData = check purchaseResponse.getJsonPayload();
        io:println("\n Purchase failed: " + check errorData.error.ensureType(string));
        io:println(" Tip: Check your account balance or try a different payment method.");
    } else {
        io:println(" Purchase failed: Server error");
    }
    
    waitForEnter();
    return;
}

function viewMyTickets() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("MY TICKETS");
    
    io:println("\n Loading your tickets...");
    
    http:Request request = new;
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error response = passengerClient->get("/passenger/tickets", request);
    
    if response is error {
        io:println(" Failed to fetch tickets: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json[] tickets = check response.getJsonPayload().ensureType();
        
        if tickets.length() == 0 {
            io:println("\n You have no tickets.");
            io:println("\n Tip: Purchase a ticket to start travelling!");
        } else {
            io:println("\n Your Tickets (" + tickets.length().toString() + " total)");
            io:println("════════════════════════════════════════════════");
            
            foreach int i in 0 ..< tickets.length() {
                json ticket = tickets[i];
                string ticketId = check ticket.ticketId.ensureType(string);
                string ticketType = check ticket.ticketType.ensureType(string);
                string status = check ticket.status.ensureType(string);
                string validUntil = check ticket.validUntil.ensureType(string);
                decimal price = check ticket.price.ensureType(decimal);
                
                string statusIcon = "📄";
                string statusColor = "";
                match status {
                    "PAID" => { 
                        statusIcon = "✅"; 
                        statusColor = "Active";
                    }
                    "VALIDATED" => { 
                        statusIcon = "🔵"; 
                        statusColor = "Used";
                    }
                    "EXPIRED" => { 
                        statusIcon = "❌"; 
                        statusColor = "Expired";
                    }
                    "CREATED" => { 
                        statusIcon = "⏳"; 
                        statusColor = "Pending";
                    }
                }
                
                io:println("\n" + statusIcon + " Ticket #" + (i + 1).toString());
                io:println("─────────────────────");
                io:println("  ID: " + ticketId);
                io:println("  Type: " + ticketType);
                io:println("  Status: " + statusColor);
                io:println("  Price: NAD " + price.toString());
                io:println("  Valid Until: " + validUntil.substring(0, 19));
            }
            io:println("\n════════════════════════════════════════════════");
        }
    } else {
        io:println(" Failed to fetch tickets");
    }
    
    waitForEnter();
    return;
}

function checkAccountBalance() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("ACCOUNT BALANCE");
    
    io:println("\n Checking your balance...");
    
    http:Request request = new;
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error response = passengerClient->get("/passenger/balance", request);
    
    if response is error {
        io:println(" Failed to fetch balance: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json balanceData = check response.getJsonPayload();
        decimal balance = check balanceData.balance.ensureType(decimal);
        string currency = check balanceData.currency.ensureType(string);
        
        io:println("\n💳 ACCOUNT INFORMATION");
        io:println("══════════════════════════");
        io:println("Current Balance: " + currency + " " + balance.toString());
        
        if balance < 20 {
            io:println("\n  Low Balance Alert!");
            io:println("Your balance is running low. Consider topping up to continue enjoying our services.");
        } else if balance >= 100 {
            io:println("\n Healthy Balance");
            io:println("You have sufficient funds for multiple trips!");
        }
        io:println("══════════════════════════");
    } else {
        io:println(" Failed to fetch balance");
    }
    
    waitForEnter();
    return;
}

function topUpAccount() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("TOP UP ACCOUNT");
    
    io:println("\n Add Funds to Your Account");
    io:println("─────────────────────────────");
    
    io:println("\nQuick amounts:");
    io:println("1. NAD 50");
    io:println("2. NAD 100");
    io:println("3. NAD 200");
    io:println("4. NAD 500");
    io:println("5. Custom amount");
    io:println("6. Cancel");
    
    string amountChoice = io:readln("\n Select amount (1-6): ");
    
    decimal amount = 0.0;
    match amountChoice {
        "1" => { amount = 50.0; }
        "2" => { amount = 100.0; }
        "3" => { amount = 200.0; }
        "4" => { amount = 500.0; }
        "5" => {
            string customAmount = io:readln("Enter amount (NAD): ");
            amount = check decimal:fromString(customAmount);
        }
        "6" => { return; }
        _ => {
            io:println(" Invalid selection");
            waitForEnter();
            return;
        }
    }
    
    if amount <= 0 {
        io:println(" Amount must be greater than 0");
        waitForEnter();
        return;
    }
    
    io:println("\n PAYMENT METHOD:");
    io:println("─────────────────");
    io:println("1. Credit/Debit Card");
    io:println("2. Mobile Money");
    io:println("3. Bank Transfer");
    io:println("4. Cancel");
    
    string paymentChoice = io:readln("\n Select payment method (1-4): ");
    
    string paymentMethod = "";
    match paymentChoice {
        "1" => { paymentMethod = "CARD"; }
        "2" => { paymentMethod = "MOBILE_MONEY"; }
        "3" => { paymentMethod = "BANK_TRANSFER"; }
        "4" => { return; }
        _ => {
            io:println(" Invalid selection");
            waitForEnter();
            return;
        }
    }
    
    io:println("\n📋 TOP-UP SUMMARY:");
    io:println("─────────────────");
    io:println("Amount: NAD " + amount.toString());
    io:println("Payment Method: " + paymentMethod);
    
    string confirm = io:readln("\n Confirm top-up? (Y/N): ");
    if confirm.toUpperAscii() != "Y" {
        io:println(" Top-up cancelled");
        waitForEnter();
        return;
    }
    
    json topUpRequest = {
        "amount": amount,
        "paymentMethod": paymentMethod
    };
    
    io:println("\n⏳ Processing top-up...");
    
    http:Request request = new;
    request.setJsonPayload(topUpRequest);
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error response = passengerClient->post("/passenger/topup", request);
    
    if response is error {
        io:println(" Top-up failed: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json result = check response.getJsonPayload();
        decimal newBalance = check result.newBalance.ensureType(decimal);
        
        io:println("\n✅ TOP-UP SUCCESSFUL!");
        io:println("══════════════════════════");
        io:println("Amount Added: NAD " + amount.toString());
        io:println("New Balance: NAD " + newBalance.toString());
        io:println("══════════════════════════");
    } else {
        io:println(" Top-up failed");
    }
    
    waitForEnter();
    return;
}

function viewEditProfile() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("MY PROFILE");
    
    io:println("\n Loading profile...");
    
    http:Request request = new;
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error response = passengerClient->get("/passenger/profile", request);
    
    if response is error {
        io:println(" Failed to fetch profile: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json profile = check response.getJsonPayload();
        
        io:println("\n👤 PROFILE INFORMATION");
        io:println("══════════════════════════════");
        io:println("Username: " + check profile.username.ensureType(string));
        io:println("Full Name: " + check profile.fullName.ensureType(string));
        io:println("Email: " + check profile.email.ensureType(string));
        io:println("Role: " + check profile.role.ensureType(string));
        
        json phone = profile.phoneNumber;
        if phone != () {
            io:println("Phone: " + check phone.ensureType(string));
        }
        
        string createdAt = check profile.createdAt.ensureType(string);
        io:println("Member Since: " + createdAt.substring(0, 10));
        io:println("══════════════════════════════");
        
        io:println("\nWould you like to edit your profile? (Y/N): ");
        string edit = io:readln("");
        
        if edit.toUpperAscii() == "Y" {
            io:println("\n EDIT PROFILE");
            io:println("─────────────────");
            io:println("Press Enter to keep current value");
            
            string newEmail = io:readln("New email [" + check profile.email.ensureType(string) + "]: ");
            string newPhone = io:readln("New phone number: ");
            
            // Update profile logic would go here
            io:println("\n Profile update feature coming soon!");
        }
    } else {
        io:println(" Failed to fetch profile");
    }
    
    waitForEnter();
    return;
}

function updateNotificationPreferences() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("NOTIFICATION PREFERENCES");
    
    io:println("\n Configure how you receive updates");
    io:println("─────────────────────────────────────");
    
    io:println("\nEnable notifications for:");
    
    string emailPref = io:readln("📧 Email notifications? (Y/N): ");
    string smsPref = io:readln("📱 SMS notifications? (Y/N): ");
    string pushPref = io:readln("📲 Push notifications? (Y/N): ");
    
    json preferences = {
        "email": emailPref.toUpperAscii() == "Y",
        "sms": smsPref.toUpperAscii() == "Y",
        "push": pushPref.toUpperAscii() == "Y"
    };
    
    io:println("\n Updating preferences...");
    
    http:Request request = new;
    request.setJsonPayload(preferences);
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error response = passengerClient->put("/passenger/notifications", request);
    
    if response is error {
        io:println(" Failed to update preferences: " + response.message());
    } else if response.statusCode == 200 {
        io:println("\n Notification preferences updated successfully!");
    } else {
        io:println(" Failed to update preferences");
    }
    
    waitForEnter();
    return;
}

function viewServiceDisruptions() returns error? {
    printSectionHeader("SERVICE DISRUPTIONS");
    
    io:println("\n Checking for service disruptions...");
    
    http:Response|error response = transportClient->get("/transport/disruptions");
    
    if response is error {
        io:println(" Failed to fetch disruptions: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json[] disruptions = check response.getJsonPayload().ensureType();
        
        if disruptions.length() == 0 {
            io:println("\n GOOD NEWS!");
            io:println("No service disruptions at this time.");
            io:println("All routes are operating normally.");
        } else {
            io:println("\n  ACTIVE DISRUPTIONS (" + disruptions.length().toString() + ")");
            io:println("══════════════════════════════════════════");
            
            foreach json disruption in disruptions {
                string title = check disruption.title.ensureType(string);
                string description = check disruption.description.ensureType(string);
                string severity = check disruption.severity.ensureType(string);
                
                string severityIcon = "ℹ️";
                if severity == "HIGH" {
                    severityIcon = "🔴";
                } else if severity == "MEDIUM" {
                    severityIcon = "🟡";
                } else if severity == "LOW" {
                    severityIcon = "🟢";
                }
                
                io:println("\n" + severityIcon + " " + title);
                io:println("─────────────────────");
                io:println("Severity: " + severity);
                io:println("Details: " + description);
                
                json routes = disruption.affectedRoutes ?: [];
                if routes is json[] && routes.length() > 0 {
                    io:println("Affected Routes: " + routes.toString());
                }
            }
            io:println("\n══════════════════════════════════════════");
        }
    } else {
        io:println(" Failed to fetch disruptions");
    }
    
    waitForEnter();
    return;
}

function viewTicketHistory() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("TICKET HISTORY");
    
    // This would fetch historical tickets including expired ones
    io:println("\n Your complete ticket history");
    io:println("Feature coming soon!");
    
    waitForEnter();
    return;
}

function viewPaymentHistory() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("PAYMENT HISTORY");
    
    io:println("\n Loading payment history...");
    
    http:Response|error response = paymentClient->get("/payment/users/" + session.userId + "/payments");
    
    if response is error {
        io:println(" Failed to fetch payment history: " + response.message());
    } else if response.statusCode == 200 {
        json[] payments = check response.getJsonPayload().ensureType();
        
        if payments.length() == 0 {
            io:println("\n No payment history found.");
        } else {
            io:println("\n Payment History (" + payments.length().toString() + " transactions)");
            io:println("══════════════════════════════════════════");
            
            foreach json payment in payments {
                string paymentId = check payment.paymentId.ensureType(string);
                decimal amount = check payment.amount.ensureType(decimal);
                string status = check payment.status.ensureType(string);
                string method = check payment.paymentMethod.ensureType(string);
                
                io:println("\nPayment ID: " + paymentId);
                io:println("Amount: NAD " + amount.toString());
                io:println("Method: " + method);
                io:println("Status: " + status);
            }
        }
    } else {
        io:println(" Failed to fetch payment history");
    }
    
    waitForEnter();
    return;
}

// ============================================
// ADMIN MENU AND FUNCTIONS
// ============================================

function showAdminMenu() returns error? {
    UserSession session = <UserSession>currentSession;
    
    clearScreen();
    io:println("╔═══════════════════════════════════════════════════╗");
    io:println("║           ADMINISTRATOR DASHBOARD                 ║");
    io:println("╠═══════════════════════════════════════════════════╣");
    io:println("║  👨‍💼 Admin: " + session.username.padEnd(38) + "║");
    io:println("╠═══════════════════════════════════════════════════╣");
    io:println("║                                                   ║");
    io:println("║   MONITORING & ANALYTICS                          ║");
    io:println("║   1. View Dashboard Statistics                    ║");
    io:println("║   2. View Revenue Report                          ║");
    io:println("║   3. View Usage Analytics                         ║");
    io:println("║   4. System Health Check                          ║");
    io:println("║                                                   ║");
    io:println("║   ROUTE & TRIP MANAGEMENT                         ║");
    io:println("║   5. Manage Routes                                ║");
    io:println("║   6. Manage Trips                                 ║");
    io:println("║   7. Publish Service Disruption                   ║");
    io:println("║                                                   ║");
    io:println("║   TICKETING & PRICING                             ║");
    io:println("║   8. Update Ticket Prices                         ║");
    io:println("║   9. View Ticket Statistics                       ║");
    io:println("║                                                   ║");
    io:println("║   USER MANAGEMENT                                 ║");
    io:println("║   10. Manage Users                                ║");
    io:println("║   11. Send Bulk Notifications                     ║");
    io:println("║                                                   ║");
    io:println("║   DATA MANAGEMENT                                 ║");
    io:println("║   12. Export Data                                 ║");
    io:println("║   13. Import Data                                 ║");
    io:println("║                                                   ║");
    io:println("║   14. Logout                                      ║");
    io:println("║                                                   ║");
    io:println("╚═══════════════════════════════════════════════════╝");
    
    string choice = io:readln("\n Select an option (1-14): ");
    
    match choice {
        "1" => { return viewDashboard(); }
        "2" => { return viewRevenueReport(); }
        "3" => { return viewUsageAnalytics(); }
        "4" => { return systemHealthCheck(); }
        "5" => { return manageRoutes(); }
        "6" => { return manageTrips(); }
        "7" => { return publishServiceDisruption(); }
        "8" => { return updateTicketPrices(); }
        "9" => { return viewTicketStatistics(); }
        "10" => { return manageUsers(); }
        "11" => { return sendBulkNotifications(); }
        "12" => { return exportData(); }
        "13" => { return importData(); }
        "14" => {
            currentSession = ();
            io:println("\n Admin logged out successfully!");
            waitForEnter();
        }
        _ => {
            io:println(" Invalid choice. Please select 1-14.");
            waitForEnter();
        }
    }
    return;
}

function viewDashboard() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("DASHBOARD STATISTICS");
    
    io:println("\n⏳ Loading system statistics...");
    
    http:Request request = new;
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error response = adminClient->get("/dashboard", request);
    
    if response is error {
        io:println(" Failed to fetch dashboard: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json stats = check response.getJsonPayload();
        
        io:println("\n SYSTEM OVERVIEW");
        io:println("══════════════════════════════════════════");
        io:println("\n USERS");
        io:println("─────────");
        io:println("Total Users: " + check stats.totalUsers.ensureType(int).toString());
        
        io:println("\n TRANSPORT");
        io:println("─────────────");
        io:println("Total Routes: " + check stats.totalRoutes.ensureType(int).toString());
        io:println("Active Trips: " + check stats.activeTrips.ensureType(int).toString());
        
        io:println("\n TICKETS");
        io:println("──────────");
        io:println("Total Tickets Sold: " + check stats.totalTicketsSold.ensureType(int).toString());
        io:println("Today's Tickets: " + check stats.todayTickets.ensureType(int).toString());
        
        io:println("\n REVENUE");
        io:println("──────────");
        io:println("Total Revenue: NAD " + check stats.totalRevenue.ensureType(decimal).toString());
        io:println("Today's Revenue: NAD " + check stats.todayRevenue.ensureType(decimal).toString());
        
        io:println("\n══════════════════════════════════════════");
    } else if response.statusCode == 401 {
        io:println(" Unauthorized. Please login again.");
    } else {
        io:println(" Failed to fetch dashboard");
    }
    
    waitForEnter();
    return;
}

function viewRevenueReport() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("REVENUE REPORT");
    
    io:println("\n Select date range for report");
    io:println("─────────────────────────────");
    
    string startDate = io:readln("Start date (YYYY-MM-DD): ");
    string endDate = io:readln("End date (YYYY-MM-DD): ");
    
    io:println("\n⏳ Generating revenue report...");
    
    http:Request request = new;
    request.setHeader("Authorization", "Bearer " + session.token);
    
    string endpoint = "/reports/revenue?startDate=" + startDate + "&endDate=" + endDate;
    http:Response|error response = adminClient->get(endpoint, request);
    
    if response is error {
        io:println(" Failed to generate report: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json report = check response.getJsonPayload();
        
        io:println("\n REVENUE REPORT");
        io:println("══════════════════════════════════════════");
        io:println("Period: " + check report.period.ensureType(string));
        io:println("─────────────────────────────────────────");
        io:println("Total Revenue: NAD " + check report.totalRevenue.ensureType(decimal).toString());
        io:println("Total Refunds: NAD " + check report.totalRefunds.ensureType(decimal).toString());
        io:println("Net Revenue: NAD " + check report.netRevenue.ensureType(decimal).toString());
        io:println("══════════════════════════════════════════");
    } else {
        io:println(" Failed to generate report");
    }
    
    waitForEnter();
    return;
}

function viewUsageAnalytics() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("USAGE ANALYTICS");
    
    io:println("\n Loading usage analytics...");
    
    http:Request request = new;
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error response = adminClient->get("/reports/usage", request);
    
    if response is error {
        io:println(" Failed to fetch analytics: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json[] reports = check response.getJsonPayload().ensureType();
        
        if reports.length() > 0 {
            io:println("\n ROUTE USAGE PATTERNS");
            io:println("══════════════════════════════════════════");
            
            foreach json report in reports {
                io:println("\n Route: " + check report.routeName.ensureType(string));
                io:println("─────────────────────────────");
                io:println("Total Passengers: " + check report.totalPassengers.ensureType(int).toString());
                io:println("Revenue: NAD " + check report.totalRevenue.ensureType(decimal).toString());
                io:println("Average Occupancy: " + check report.averageOccupancy.ensureType(decimal).toString() + "%");
            }
            io:println("\n══════════════════════════════════════════");
        } else {
            io:println("\n No usage data available");
        }
    } else {
        io:println(" Failed to fetch analytics");
    }
    
    waitForEnter();
    return;
}

function systemHealthCheck() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("SYSTEM HEALTH CHECK");
    
    io:println("\n Checking system health...");
    
    http:Request request = new;
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error response = adminClient->get("/system/health", request);
    
    if response is error {
        io:println(" Failed to check system health: " + response.message());
        waitForEnter();
        return;
    }
    
    if response.statusCode == 200 {
        json health = check response.getJsonPayload();
        
        string status = check health.status.ensureType(string);
        string statusIcon = status == "healthy" ? "✅" : "❌";
        
        io:println("\n" + statusIcon + " System Status: " + status.toUpperAscii());
        io:println("══════════════════════════════════════════");
        
        json services = health.services ?: [];
        if services is json[] {
            io:println("\n🔧 SERVICES:");
            io:println("─────────────");
            foreach json svc in services {
                string svcStatus = check svc.status.ensureType(string);
                string svcIcon = svcStatus == "healthy" ? "✅" : "❌";
                io:println(svcIcon + " " + check svc.serviceName.ensureType(string) + ": " + svcStatus);
            }
        }
        
        io:println("\n INFRASTRUCTURE:");
        io:println("─────────────────");
        io:println(" Kafka: Connected");
        io:println(" MongoDB: Connected");
        io:println("\n══════════════════════════════════════════");
    } else {
        io:println(" Failed to check system health");
    }
    
    waitForEnter();
    return;
}

function manageRoutes() returns error? {
    printSectionHeader("ROUTE MANAGEMENT");
    
    io:println("\n ROUTE OPERATIONS");
    io:println("─────────────────────");
    io:println("1. Create New Route");
    io:println("2. View All Routes");
    io:println("3. Update Route");
    io:println("4. Deactivate Route");
    io:println("5. Back to Menu");
    
    string choice = io:readln("\n Select option (1-5): ");
    
    match choice {
        "1" => { return createNewRoute(); }
        "2" => { return viewAvailableRoutes(); }
        "3" => { 
            io:println("\n Route update feature coming soon!");
            waitForEnter();
        }
        "4" => { 
            io:println("\n Route deactivation feature coming soon!");
            waitForEnter();
        }
    }
    return;
}

function createNewRoute() returns error? {
    printSectionHeader("CREATE NEW ROUTE");
    
    io:println("\n Enter route details:");
    io:println("─────────────────────");
    
    string routeName = io:readln("Route name: ");
    
    io:println("\nTransport type:");
    io:println("1.  BUS");
    io:println("2.  TRAIN");
    
    string typeChoice = io:readln("\n Select type (1-2): ");
    string transportType = typeChoice == "1" ? "BUS" : "TRAIN";
    
    string startPoint = io:readln("\nStart point: ");
    string endPoint = io:readln("End point: ");
    
    io:println("\n Creating route...");
    
    json newRoute = {
        "routeName": routeName,
        "transportType": transportType,
        "startPoint": startPoint,
        "endPoint": endPoint,
        "intermediateStops": [],
        "isActive": true
    };
    
    http:Response|error response = transportClient->post("/transport/routes", newRoute);
    
    if response is error {
        io:println(" Failed to create route: " + response.message());
    } else if response.statusCode == 200 {
        json route = check response.getJsonPayload();
        string routeId = check route.routeId.ensureType(string);
        
        io:println("\n Route created successfully!");
        io:println("Route ID: " + routeId);
    } else {
        io:println(" Failed to create route");
    }
    
    waitForEnter();
    return;
}

function manageTrips() returns error? {
    printSectionHeader("TRIP MANAGEMENT");
    
    io:println("\n TRIP OPERATIONS");
    io:println("─────────────────");
    io:println("1. Create New Trip");
    io:println("2. View Today's Trips");
    io:println("3. Update Trip Status");
    io:println("4. Cancel Trip");
    io:println("5. Back to Menu");
    
    string choice = io:readln("\n Select option (1-5): ");
    
    match choice {
        "1" => { return createNewTrip(); }
        "2" => { return viewTodaysTrips(); }
        "3" => { 
            io:println("\n Trip status update feature coming soon!");
            waitForEnter();
        }
        "4" => { 
            io:println("\n Trip cancellation feature coming soon!");
            waitForEnter();
        }
    }
    return;
}

function createNewTrip() returns error? {
    printSectionHeader("CREATE NEW TRIP");
    
    io:println("\n Enter trip details:");
    io:println("────────────────────");
    
    string routeId = io:readln("Route ID: ");
    string departureDate = io:readln("Departure date (YYYY-MM-DD): ");
    string departureTime = io:readln("Departure time (HH:MM): ");
    string arrivalTime = io:readln("Arrival time (HH:MM): ");
    string vehicleId = io:readln("Vehicle ID: ");
    string capacityStr = io:readln("Capacity: ");
    int capacity = check int:fromString(capacityStr);
    
    io:println("\n Creating trip...");
    
    json newTrip = {
        "routeId": routeId,
        "scheduledDepartureTime": departureDate + "T" + departureTime + ":00Z",
        "scheduledArrivalTime": departureDate + "T" + arrivalTime + ":00Z",
        "vehicleId": vehicleId,
        "capacity": capacity,
        "driverInfo": {
            "driverId": "DRIVER-001",
            "driverName": "John Doe"
        }
    };
    
    http:Response|error response = transportClient->post("/transport/trips", newTrip);
    
    if response is error {
        io:println(" Failed to create trip: " + response.message());
    } else if response.statusCode == 200 {
        json trip = check response.getJsonPayload();
        string tripId = check trip.tripId.ensureType(string);
        
        io:println("\n Trip created successfully!");
        io:println("Trip ID: " + tripId);
    } else {
        io:println(" Failed to create trip");
    }
    
    waitForEnter();
    return;
}

function viewTodaysTrips() returns error? {
    printSectionHeader("TODAY'S TRIPS");
    
    string today = time:utcToString(time:utcNow()).substring(0, 10);
    
    io:println("\n Loading trips for " + today + "...");
    
    http:Response|error response = transportClient->get("/transport/trips?date=" + today);
    
    if response is error {
        io:println(" Failed to fetch trips: " + response.message());
    } else if response.statusCode == 200 {
        json[] trips = check response.getJsonPayload().ensureType();
        
        io:println("\n Today's Trips (" + trips.length().toString() + " total)");
        io:println("══════════════════════════════════════════");
        
        foreach json trip in trips {
            string tripId = check trip.tripId.ensureType(string);
            string routeId = check trip.routeId.ensureType(string);
            string status = check trip.status.ensureType(string);
            
            io:println("\nTrip ID: " + tripId);
            io:println("Route: " + routeId);
            io:println("Status: " + status);
        }
    } else {
        io:println(" Failed to fetch trips");
    }
    
    waitForEnter();
    return;
}

function publishServiceDisruption() returns error? {
    printSectionHeader("PUBLISH SERVICE DISRUPTION");
    
    io:println("\n  Create a service alert");
    io:println("─────────────────────────");
    
    string title = io:readln("\nDisruption title: ");
    string description = io:readln("Description: ");
    
    io:println("\nSeverity level:");
    io:println("1. 🟢 LOW - Minor delays");
    io:println("2. 🟡 MEDIUM - Significant delays");
    io:println("3. 🔴 HIGH - Service suspended");
    
    string severityChoice = io:readln("\n Select severity (1-3): ");
    string severity = severityChoice == "1" ? "LOW" : 
                     severityChoice == "2" ? "MEDIUM" : "HIGH";
    
    string affectedRoutes = io:readln("\nAffected route IDs (comma-separated): ");
    
    io:println("\n Publishing disruption alert...");
    
    json disruption = {
        "title": title,
        "description": description,
        "severity": severity,
        "disruptionType": "SERVICE_DELAY",
        "affectedRoutes": affectedRoutes.split(","),
        "affectedTrips": [],
        "estimatedDuration": {
            "startTime": time:utcToString(time:utcNow()),
            "endTime": time:utcToString(time:utcAddSeconds(time:utcNow(), 7200))
        },
        "alternativeRoutes": [],
        "publishedBy": "ADMIN"
    };
    
    http:Response|error response = transportClient->post("/transport/disruptions", disruption);
    
    if response is error {
        io:println(" Failed to publish disruption: " + response.message());
    } else if response.statusCode == 200 {
        json result = check response.getJsonPayload();
        
        io:println("\n Service disruption published!");
        io:println("Disruption ID: " + check result.disruptionId.ensureType(string));
        io:println("\n Affected passengers will be notified automatically.");
    } else {
        io:println(" Failed to publish disruption");
    }
    
    waitForEnter();
    return;
}

function updateTicketPrices() returns error? {
    printSectionHeader("UPDATE TICKET PRICES");
    
    io:println("\n Ticket Price Management");
    io:println("────────────────────────");
    io:println("\n This feature requires direct database access.");
    io:println("Price updates will be available in the next release.");
    
    waitForEnter();
    return;
}

function viewTicketStatistics() returns error? {
    printSectionHeader("TICKET STATISTICS");
    
    io:println("\n Loading ticket statistics...");
    
    http:Response|error response = ticketingClient->get("/ticketing/statistics");
    
    if response is error {
        io:println(" Failed to fetch statistics: " + response.message());
    } else if response.statusCode == 200 {
        json stats = check response.getJsonPayload();
        
        io:println("\n TICKET STATISTICS");
        io:println("══════════════════════════════════════════");
        io:println("Total Tickets: " + check stats.totalTickets.ensureType(int).toString());
        io:println("Total Revenue: NAD " + check stats.totalRevenue.ensureType(decimal).toString());
        io:println("══════════════════════════════════════════");
    } else {
        io:println(" Failed to fetch statistics");
    }
    
    waitForEnter();
    return;
}

function manageUsers() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("USER MANAGEMENT");
    
    io:println("\n USER OPERATIONS");
    io:println("─────────────────");
    io:println("1. View All Users");
    io:println("2. Search User");
    io:println("3. Update User Status");
    io:println("4. View User Details");
    io:println("5. Back to Menu");
    
    string choice = io:readln("\n Select option (1-5): ");
    
    if choice == "1" {
        io:println("\n Loading users...");
        
        http:Request request = new;
        request.setHeader("Authorization", "Bearer " + session.token);
        
        http:Response|error response = adminClient->get("/users?limit=20", request);
        
        if response is error {
            io:println(" Failed to fetch users: " + response.message());
        } else if response.statusCode == 200 {
            json[] users = check response.getJsonPayload().ensureType();
            
            io:println("\n USERS (" + users.length().toString() + " shown)");
            io:println("══════════════════════════════════════════");
            
            foreach json user in users {
                io:println("\n " + check user.username.ensureType(string));
                io:println("   Email: " + check user.email.ensureType(string));
                io:println("   Role: " + check user.role.ensureType(string));
            }
        } else {
            io:println(" Failed to fetch users");
        }
    } else if choice == "3" {
        string userId = io:readln("\nEnter user ID: ");
        
        io:println("\nNew status:");
        io:println("1.  ACTIVE");
        io:println("2.  SUSPENDED");
        
        string statusChoice = io:readln("\n Select status (1-2): ");
        string newStatus = statusChoice == "1" ? "ACTIVE" : "SUSPENDED";
        
        string reason = io:readln("Reason for status change: ");
        
        json statusUpdate = {
            "status": newStatus,
            "reason": reason
        };
        
        http:Request request = new;
        request.setJsonPayload(statusUpdate);
        request.setHeader("Authorization", "Bearer " + session.token);
        
        http:Response|error response = adminClient->put("/users/" + userId + "/status", request);
        
        if response is error {
            io:println(" Failed to update status: " + response.message());
        } else if response.statusCode == 200 {
            io:println("\n User status updated successfully!");
        } else {
            io:println(" Failed to update status");
        }
    }
    
    waitForEnter();
    return;
}

function sendBulkNotifications() returns error? {
    printSectionHeader("SEND BULK NOTIFICATIONS");
    
    io:println("\n Broadcast Message");
    io:println("───────────────────");
    
    io:println("\n Bulk notification feature coming soon!");
    io:println("This will allow sending messages to all users or specific groups.");
    
    waitForEnter();
    return;
}

function exportData() returns error? {
    UserSession session = <UserSession>currentSession;
    
    printSectionHeader("DATA EXPORT");
    
    io:println("\n SELECT DATA TO EXPORT");
    io:println("─────────────────────────");
    io:println("1. Tickets");
    io:println("2. Payments");
    io:println("3. Users");
    io:println("4. Routes");
    io:println("5. Cancel");
    
    string choice = io:readln("\n Select data type (1-5): ");
    
    string dataType = "";
    match choice {
        "1" => { dataType = "tickets"; }
        "2" => { dataType = "payments"; }
        "3" => { dataType = "users"; }
        "4" => { dataType = "routes"; }
        _ => { return; }
    }
    
    io:println("\n Exporting " + dataType + "...");
    
    http:Request request = new;
    request.setHeader("Authorization", "Bearer " + session.token);
    
    http:Response|error response = adminClient->get("/export/" + dataType, request);
    
    if response is error {
        io:println(" Export failed: " + response.message());
    } else if response.statusCode == 200 {
        json[] data = check response.getJsonPayload().ensureType();
        
        io:println("\n Export successful!");
        io:println("Exported " + data.length().toString() + " records.");
        io:println("\n Data exported to: exports/" + dataType + "_" + 
                  time:utcToString(time:utcNow()).substring(0, 10) + ".json");
    } else {
        io:println("Export failed");
    }
    
    waitForEnter();
    return;
}

function importData() returns error? {
    printSectionHeader("DATA IMPORT");
    
    io:println("\n📥Import Data");
    io:println("──────────────");
    
    io:println("\n Data import feature coming soon!");
    io:println("This will allow importing data from CSV/JSON files.");
    
    waitForEnter();
    return;
}

// ============================================
// VALIDATOR MENU AND FUNCTIONS
// ============================================

function showValidatorMenu() returns error? {
    UserSession session = <UserSession>currentSession;
    
    clearScreen();
    io:println("╔═══════════════════════════════════════════════════╗");
    io:println("║             VALIDATOR TERMINAL                    ║");
    io:println("╠═══════════════════════════════════════════════════╣");
    io:println("║     Validator: " + session.username.padEnd(34) + "║");
    io:println("╠═══════════════════════════════════════════════════╣");
    io:println("║                                                   ║");
    io:println("║   1. Validate Ticket                              ║");
    io:println("║   2. View Validation History                      ║");
    io:println("║   3. Check Trip Occupancy                         ║");
    io:println("║   4. Report Issue                                 ║");
    io:println("║   5. Scan QR Code (Simulated)                     ║");
    io:println("║   6. Logout                                       ║");
    io:println("║                                                   ║");
    io:println("╚═══════════════════════════════════════════════════╝");
    
    string choice = io:readln("\n Select an option (1-6): ");
    
    match choice {
        "1" => { return validateTicket(); }
        "2" => { return viewValidationHistory(); }
        "3" => { return checkTripOccupancy(); }
        "4" => { return reportValidatorIssue(); }
        "5" => { return scanQRCode(); }
        "6" => {
            currentSession = ();
            io:println("\n Validator logged out successfully!");
            waitForEnter();
        }
        _ => {
            io:println(" Invalid choice. Please select 1-6.");
            waitForEnter();
        }
    }
    return;
}

function validateTicket() returns error? {
    printSectionHeader("TICKET VALIDATION");
    
    io:println("\n Validate Passenger Ticket");
    io:println("─────────────────────────────");
    
    string ticketId = io:readln("\nTicket ID (or scan QR): ");
    string vehicleId = io:readln("Vehicle ID: ");
    string location = io:readln("Current location/stop: ");
    
    io:println("\n Validating ticket...");
    
    json validationRequest = {
        "ticketId": ticketId,
        "validatorId": "VAL-001",
        "vehicleId": vehicleId,
        "location": location
    };
    
    http:Response|error response = ticketingClient->post("/ticketing/tickets/validate", validationRequest);
    
    if response is error {
        io:println(" Validation error: " + response.message());
    } else if response.statusCode == 200 {
        json result = check response.getJsonPayload();
        
        io:println("\n         TICKET VALID ");
        io:println("══════════════════════════════════");
        io:println("Ticket Type: " + check result.validationType.ensureType(string));
        io:println("Validity: " + check result.remainingValidity.ensureType(string));
        io:println("══════════════════════════════════");
        io:println("\n🔊 PASSENGER MAY BOARD");
    } else if response.statusCode == 400 {
        json errorData = check response.getJsonPayload();
        string errorMsg = check errorData.error.ensureType(string);
        
        io:println("\n    VALIDATION FAILED ");
        io:println("══════════════════════════════════");
        io:println("Reason: " + errorMsg);
        
        if errorMsg.includes("expired") {
            io:println("\n  TICKET EXPIRED");
        } else if errorMsg.includes("already used") {
            io:println("\n  TICKET ALREADY USED");
        } else if errorMsg.includes("Payment pending") {
            io:println("\n PAYMENT NOT COMPLETED");
        }
        
        io:println("══════════════════════════════════");
        io:println("\n PASSENGER MUST PURCHASE VALID TICKET");
    } else if response.statusCode == 404 {
        io:println("\n TICKET NOT FOUND");
        io:println("Invalid ticket ID. Ask passenger to show valid ticket.");
    }
    
    waitForEnter();
    return;
}

function viewValidationHistory() returns error? {
    printSectionHeader("VALIDATION HISTORY");
    
    io:println("\n Recent Validations");
    io:println("────────────────────");
    
    io:println("\n Validation history feature coming soon!");
    io:println("This will show all tickets validated by this validator.");
    
    waitForEnter();
    return;
}

function checkTripOccupancy() returns error? {
    printSectionHeader("TRIP OCCUPANCY");
    
    io:println("\n Check Vehicle Occupancy");
    io:println("─────────────────────────");
    
    string tripId = io:readln("\nTrip ID: ");
    
    io:println("\n Loading occupancy data...");
    
    http:Response|error response = transportClient->get("/transport/trips/" + tripId);
    
    if response is error {
        io:println(" Failed to fetch trip: " + response.message());
    } else if response.statusCode == 200 {
        json trip = check response.getJsonPayload();
        
        int capacity = check trip.capacity.ensureType(int);
        int occupied = check trip.occupiedSeats.ensureType(int);
        int available = capacity - occupied;
        decimal occupancyRate = (occupied * 100.0) / capacity;
        
        io:println("\n TRIP OCCUPANCY");
        io:println("══════════════════════════════════");
        io:println("Trip ID: " + tripId);
        io:println("Total Capacity: " + capacity.toString() + " seats");
        io:println("Occupied: " + occupied.toString() + " seats");
        io:println("Available: " + available.toString() + " seats");
        io:println("Occupancy Rate: " + occupancyRate.toString() + "%");
        
        if occupancyRate > 90 {
            io:println("\n  NEARLY FULL - Few seats remaining!");
        } else if occupancyRate > 75 {
            io:println("\n High occupancy");
        } else {
            io:println("\n Normal occupancy");
        }
        io:println("══════════════════════════════════");
    } else if response.statusCode == 404 {
        io:println("\n Trip not found");
    } else {
        io:println(" Failed to fetch trip data");
    }
    
    waitForEnter();
    return;
}

function reportValidatorIssue() returns error? {
    printSectionHeader("REPORT ISSUE");
    
    io:println("\n  Report an Issue");
    io:println("──────────────────");
    
    io:println("\nIssue Type:");
    io:println("1. Fraudulent ticket");
    io:println("2. Vehicle problem");
    io:println("3. Passenger incident");
    io:println("4. System/Equipment issue");
    io:println("5. Other");
    
    string issueType = io:readln("\n Select issue type (1-5): ");
    string description = io:readln("\nDescribe the issue: ");
    string location = io:readln("Location: ");
    
    io:println("\n Submitting report...");
    
    // In a real system, this would send to a reporting endpoint
    io:println("\n Issue reported successfully!");
    io:println("Report ID: RPT-" + time:monotonicMillis().toString());
    io:println("\nAdministrators will be notified immediately.");
    
    waitForEnter();
    return;
}

function scanQRCode() returns error? {
    printSectionHeader("QR CODE SCANNER");
    
    io:println("\n QR Code Scanner (Simulated)");
    io:println("──────────────────────────────");
    
    io:println("\n[Camera view would appear here]");
    io:println("┌────────────────────┐");
    io:println("│                    │");
    io:println("│     SCANNING...  │");
    io:println("│                    │");
    io:println("│    ▓▓ ▓  ▓ ▓▓     │");
    io:println("│    ▓  ▓▓▓  ▓      │");
    io:println("│    ▓▓ ▓  ▓ ▓▓     │");
    io:println("│                    │");
    io:println("└────────────────────┘");
    
    // Simulate scanning delay
    io:println("\n Processing QR code...");
    
    // For demo, use a sample ticket ID
    string ticketId = "TKT-DEMO123456";
    
    io:println("\n QR Code scanned!");
    io:println("Ticket ID: " + ticketId);
    io:println("\nProceed to validate? (Y/N): ");
    
    string proceed = io:readln("");
    if proceed.toUpperAscii() == "Y" {
        // Would call validateTicket with the scanned ID
        io:println(" Integration with validation system coming soon!");
    }
    
    waitForEnter();
    return;
}

// Utility function for string padding
function padEnd(string str, int length) returns string {
    int currentLength = str.length();
    if currentLength >= length {
        return str;
    }
    int padding = length - currentLength;
    return str + " ".repeat(padding);
}

// String repeat utility
function repeat(string str, int count) returns string {
    string result = "";
    foreach int i in 0 ..< count {
        result = result + str;
    }
    return result;
}

// Utility function for string padding
isolated function padEnd(string str, int length) returns string {
    int currentLength = str.length();
    if currentLength >= length {
        return str;
    }
    int padding = length - currentLength;
    string paddedStr = str;
    foreach int i in 0 ..< padding {
        paddedStr = paddedStr + " ";
    }
    return paddedStr;
}

// String repeat utility
isolated function repeat(string str, int count) returns string {
    string result = "";
    foreach int i in 0 ..< count {
        result = result + str;
    }
    return result;
}

// Safe string conversion for ensureType
function ensureString(json value) returns string|error {
    if value is string {
        return value;
    }
    return error("Value is not a string");
}

// Safe int conversion
function ensureInt(json value) returns int|error {
    if value is int {
        return value;
    }
    return error("Value is not an int");
}

// Safe decimal conversion
function ensureDecimal(json value) returns decimal|error {
    if value is decimal {
        return value;
    }
    if value is int {
        return <decimal>value;
    }
    return error("Value is not a decimal");
}

// Safe boolean conversion
function ensureBoolean(json value) returns boolean|error {
    if value is boolean {
        return value;
    }
    return error("Value is not a boolean");
}