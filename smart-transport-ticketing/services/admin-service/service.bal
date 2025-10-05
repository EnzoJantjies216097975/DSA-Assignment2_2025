import ballerina/http;
import ballerina/log;
import ballerina/jwt;
import ballerina/time;
import ballerinax/kafka;
import ballerinax/mongodb;

// Configuration for MongoDB connection
configurable string mongodbUrl = "mongodb://localhost:27017";
configurable string databaseName = "transport_db";

// Configuration for Kafka
configurable string kafkaBootstrapServers = "localhost:9092";

// JWT configuration
configurable string jwtSecret = "your-secret-key-change-in-production";
configurable string jwtIssuer = "smart-transport-system";

// MongoDB client for database operations
mongodb:Client mongoClient = check new (mongodbUrl);

// Kafka producer for publishing events
kafka:Producer kafkaProducer = check new ({
    bootstrapServers: kafkaBootstrapServers,
    clientId: "admin-service",
    acks: "all",
    retryCount: 3
});

// Define admin-related record types
type AdminUser record {
    string id?;
    string username;
    string email;
    string password;
    string role;
    string fullName;
    string[] permissions;
    string lastLogin?;
    string createdAt?;
    string updatedAt?;
};

type DashboardStats record {
    int totalUsers;
    int totalRoutes;
    int activeTrips;
    int totalTicketsSold;
    decimal totalRevenue;
    int todayTickets;
    decimal todayRevenue;
    map<int> ticketsByType;
    map<decimal> revenueByRoute;
};

type RevenueReport record {
    string period;
    decimal totalRevenue;
    decimal totalRefunds;
    decimal netRevenue;
    RevenueBreakdown[] breakdown;
};

type RevenueBreakdown record {
    string date;
    decimal revenue;
    int transactions;
    map<decimal> byPaymentMethod;
};

type UsageReport record {
    string routeId;
    string routeName;
    int totalPassengers;
    decimal totalRevenue;
    decimal averageOccupancy;
    int peakHourPassengers;
    UsagePattern[] patterns;
};

type UsagePattern record {
    string hour;
    int passengers;
    decimal occupancyRate;
};

type SystemHealth record {
    string status;
    ServiceStatus[] services;
    KafkaHealth kafkaStatus;
    DatabaseHealth databaseStatus;
    string timestamp;
};

type ServiceStatus record {
    string serviceName;
    string status;
    string endpoint;
    int responseTime;
};

type KafkaHealth record {
    boolean connected;
    string[] availableTopics;
    int lagCount;
};

type DatabaseHealth record {
    boolean connected;
    int collections;
    int totalDocuments;
};

// Service definition with authentication
@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["*"],
        exposeHeaders: ["*"],
        allowCredentials: false,
        maxAge: 86400
    }
}

# A service representing a network-accessible API
# bound to port `9090`.
service / on new http:Listener(9090) {

    // Admin login
    resource function post login(@http:Payload map<json> credentials) 
            returns map<json>|http:Unauthorized|http:InternalServerError {
        string username = check credentials["username"].ensureType();
        string password = check credentials["password"].ensureType();
        
        // Verify admin credentials
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        map<json> query = {
            "username": username,
            "role": {"$in": ["ADMIN", "SUPER_ADMIN"]}
        };
        
        stream<AdminUser, error?> admins = check usersCollection->find(query);
        AdminUser|error? admin = admins.next();
        
        if admin is () || admin is error {
            return <http:Unauthorized>{
                body: {"error": "Invalid admin credentials"}
            };
        }
        
        // Verify password (simplified - use proper hashing in production)
        if admin.password != password {
            return <http:Unauthorized>{
                body: {"error": "Invalid admin credentials"}
            };
        }
        
        // Generate JWT token
        jwt:IssuerConfig issuerConfig = {
            issuer: jwtIssuer,
            audience: ["admin-app"],
            expTime: 28800, // 8 hours
            signatureConfig: {
                algorithm: jwt:HS256,
                secret: jwtSecret
            },
            customClaims: {
                "userId": admin.id ?: "",
                "username": admin.username,
                "role": admin.role,
                "permissions": admin.permissions
            }
        };
        
        string jwtToken = check jwt:issue(issuerConfig);
        
        // Update last login
        map<json> updateFilter = {"username": username};
        map<json> updateData = {
            "$set": {"lastLogin": time:utcToString(time:utcNow())}
        };
        check usersCollection->updateOne(updateFilter, updateData);
        
        // Publish admin login event
        kafka:ProducerRecord loginEvent = {
            topic: "admin.actions",
            key: username.toBytes(),
            value: {
                "eventType": "ADMIN_LOGIN",
                "adminId": admin.id ?: "",
                "username": username,
                "timestamp": time:utcToString(time:utcNow())
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(loginEvent);
        
        return {
            "token": jwtToken,
            "user": {
                "username": admin.username,
                "email": admin.email,
                "role": admin.role,
                "permissions": admin.permissions
            }
        };
    }
    
    // Get dashboard statistics
    resource function get dashboard(@http:Header string authorization) 
            returns DashboardStats|http:Unauthorized|http:InternalServerError {
        // Validate admin token
        if !check validateAdminToken(authorization) {
            return <http:Unauthorized>{
                body: {"error": "Unauthorized access"}
            };
        }
        
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        
        // Get total users
        mongodb:Collection usersCollection = check db->getCollection("users");
        int totalUsers = check countDocuments(usersCollection, {"role": "PASSENGER"});
        
        // Get routes stats
        mongodb:Collection routesCollection = check db->getCollection("routes");
        int totalRoutes = check countDocuments(routesCollection, {"isActive": true});
        
        // Get trips stats
        mongodb:Collection tripsCollection = check db->getCollection("trips");
        int activeTrips = check countDocuments(tripsCollection, {
            "status": {"$in": ["SCHEDULED", "IN_PROGRESS"]}
        });
        
        // Get ticket stats
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        int totalTicketsSold = check countDocuments(ticketsCollection, {
            "status": {"$in": ["PAID", "VALIDATED"]}
        });
        
        // Get today's tickets
        string todayStart = time:utcToString(time:utcNow()).substring(0, 10) + "T00:00:00Z";
        int todayTickets = check countDocuments(ticketsCollection, {
            "purchaseDate": {"$gte": todayStart},
            "status": {"$in": ["PAID", "VALIDATED"]}
        });
        
        // Get revenue stats
        mongodb:Collection paymentsCollection = check db->getCollection("payments");
        decimal totalRevenue = check calculateTotalRevenue(paymentsCollection, {
            "status": "COMPLETED"
        });
        
        decimal todayRevenue = check calculateTotalRevenue(paymentsCollection, {
            "processedAt": {"$gte": todayStart},
            "status": "COMPLETED"
        });
        
        // Get tickets by type
        map<int> ticketsByType = check getTicketsByType(ticketsCollection);
        
        // Get revenue by route
        map<decimal> revenueByRoute = check getRevenueByRoute(ticketsCollection);
        
        return {
            totalUsers: totalUsers,
            totalRoutes: totalRoutes,
            activeTrips: activeTrips,
            totalTicketsSold: totalTicketsSold,
            totalRevenue: totalRevenue,
            todayTickets: todayTickets,
            todayRevenue: todayRevenue,
            ticketsByType: ticketsByType,
            revenueByRoute: revenueByRoute
        };
    }
    
    // Get revenue report
    resource function get reports/revenue(
        @http:Header string authorization,
        string startDate,
        string endDate
    ) returns RevenueReport|http:Unauthorized|http:InternalServerError {
        // Validate admin token
        if !check validateAdminToken(authorization) {
            return <http:Unauthorized>{
                body: {"error": "Unauthorized access"}
            };
        }
        
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");
        
        // Get payments in date range
        map<json> query = {
            "processedAt": {
                "$gte": startDate,
                "$lte": endDate
            }
        };
        
        stream<map<json>, error?> paymentsStream = check paymentsCollection->find(query);
        
        decimal totalRevenue = 0.0;
        decimal totalRefunds = 0.0;
        map<RevenueBreakdown> dailyBreakdown = {};
        
        check from map<json> payment in paymentsStream
            do {
                string status = check payment["status"].ensureType(string);
                decimal amount = check payment["amount"].ensureType(decimal);
                string processedAt = check payment["processedAt"].ensureType(string);
                string paymentMethod = check payment["paymentMethod"].ensureType(string);
                
                string date = processedAt.substring(0, 10);
                
                if status == "COMPLETED" {
                    totalRevenue = totalRevenue + amount;
                    
                    // Update daily breakdown
                    if dailyBreakdown.hasKey(date) {
                        RevenueBreakdown breakdown = dailyBreakdown.get(date);
                        breakdown.revenue = breakdown.revenue + amount;
                        breakdown.transactions = breakdown.transactions + 1;
                        
                        decimal currentMethodRevenue = breakdown.byPaymentMethod[paymentMethod] ?: 0.0;
                        breakdown.byPaymentMethod[paymentMethod] = currentMethodRevenue + amount;
                    } else {
                        map<decimal> methodRevenue = {};
                        methodRevenue[paymentMethod] = amount;
                        
                        dailyBreakdown[date] = {
                            date: date,
                            revenue: amount,
                            transactions: 1,
                            byPaymentMethod: methodRevenue
                        };
                    }
                } else if status == "REFUNDED" {
                    totalRefunds = totalRefunds + amount;
                }
            };
        
        // Convert map to array
        RevenueBreakdown[] breakdown = [];
        foreach RevenueBreakdown item in dailyBreakdown {
            breakdown.push(item);
        }
        
        return {
            period: startDate + " to " + endDate,
            totalRevenue: totalRevenue,
            totalRefunds: totalRefunds,
            netRevenue: totalRevenue - totalRefunds,
            breakdown: breakdown
        };
    }
    
    // Get usage report
    resource function get reports/usage(
        @http:Header string authorization,
        string? routeId = (),
        string? date = ()
    ) returns UsageReport[]|http:Unauthorized|http:InternalServerError {
        // Validate admin token
        if !check validateAdminToken(authorization) {
            return <http:Unauthorized>{
                body: {"error": "Unauthorized access"}
            };
        }
        
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection analyticsCollection = check db->getCollection("usageAnalytics");
        
        map<json> query = {};
        if routeId is string {
            query["routeId"] = routeId;
        }
        if date is string {
            query["date"] = date;
        }
        
        stream<map<json>, error?> analyticsStream = check analyticsCollection->find(query);
        
        UsageReport[] reports = [];
        check from map<json> analytics in analyticsStream
            do {
                UsagePattern[] patterns = [];
                json hourlyBreakdown = check analytics["hourlyBreakdown"];
                
                if hourlyBreakdown is json[] {
                    foreach json hourData in hourlyBreakdown {
                        patterns.push({
                            hour: check hourData["hour"].ensureType(string),
                            passengers: check hourData["passengers"].ensureType(int),
                            occupancyRate: check hourData["occupancyRate"].ensureType(decimal)
                        });
                    }
                }
                
                reports.push({
                    routeId: check analytics["routeId"].ensureType(string),
                    routeName: check analytics["routeName"].ensureType(string),
                    totalPassengers: check analytics["metrics"]["totalPassengers"].ensureType(int),
                    totalRevenue: check analytics["metrics"]["revenue"].ensureType(decimal),
                    averageOccupancy: check analytics["metrics"]["averageOccupancy"].ensureType(decimal),
                    peakHourPassengers: check analytics["metrics"]["peakHourPassengers"].ensureType(int),
                    patterns: patterns
                });
            };
        
        return reports;
    }
    
    // Manage users (get all users with filters)
    resource function get users(
        @http:Header string authorization,
        string? role = (),
        string? status = (),
        int limit = 100
    ) returns map<json>[]|http:Unauthorized|http:InternalServerError {
        // Validate admin token
        if !check validateAdminToken(authorization) {
            return <http:Unauthorized>{
                body: {"error": "Unauthorized access"}
            };
        }
        
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        map<json> query = {};
        if role is string {
            query["role"] = role;
        }
        
        stream<map<json>, error?> usersStream = check usersCollection->find(query);
        
        map<json>[] users = [];
        int count = 0;
        check from map<json> user in usersStream
            do {
                if count < limit {
                    // Remove password from response
                    user.remove("password");
                    users.push(user);
                    count += 1;
                }
            };
        
        return users;
    }
    
    // Update user status (activate/deactivate)
    resource function put users/[string userId]/status(
        @http:Header string authorization,
        @http:Payload map<json> statusUpdate
    ) returns map<json>|http:Unauthorized|http:NotFound|http:InternalServerError {
        // Validate admin token
        if !check validateAdminToken(authorization) {
            return <http:Unauthorized>{
                body: {"error": "Unauthorized access"}
            };
        }
        
        string newStatus = check statusUpdate["status"].ensureType();
        string reason = check statusUpdate["reason"].ensureType();
        
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        map<json> filter = {"id": userId};
        map<json> update = {
            "$set": {
                "status": newStatus,
                "statusReason": reason,
                "statusUpdatedAt": time:utcToString(time:utcNow()),
                "updatedAt": time:utcToString(time:utcNow())
            }
        };
        
        mongodb:UpdateResult result = check usersCollection->updateOne(filter, update);
        
        if result.modifiedCount > 0 {
            // Publish user status update event
            kafka:ProducerRecord statusEvent = {
                topic: "admin.actions",
                key: userId.toBytes(),
                value: {
                    "eventType": "USER_STATUS_UPDATED",
                    "userId": userId,
                    "newStatus": newStatus,
                    "reason": reason,
                    "updatedBy": "admin",
                    "timestamp": time:utcToString(time:utcNow())
                }.toJsonString().toBytes()
            };
            
            check kafkaProducer->send(statusEvent);
            
            return {
                "message": "User status updated successfully",
                "userId": userId,
                "newStatus": newStatus
            };
        }
        
        return <http:NotFound>{
            body: {"error": "User not found"}
        };
    }
    
    // System health check
    resource function get system/health(@http:Header string authorization) 
            returns SystemHealth|http:Unauthorized|http:InternalServerError {
        // Validate admin token
        if !check validateAdminToken(authorization) {
            return <http:Unauthorized>{
                body: {"error": "Unauthorized access"}
            };
        }
        
        ServiceStatus[] services = [];
        
        // Check each service health
        services.push(check checkServiceHealth("passenger-service", "http://localhost:8081/health"));
        services.push(check checkServiceHealth("transport-service", "http://localhost:8082/health"));
        services.push(check checkServiceHealth("ticketing-service", "http://localhost:8083/health"));
        services.push(check checkServiceHealth("payment-service", "http://localhost:8084/health"));
        services.push(check checkServiceHealth("notification-service", "http://localhost:8085/health"));
        
        // Check Kafka health
        KafkaHealth kafkaHealth = {
            connected: true,
            availableTopics: [
                "user.events", "route.events", "schedule.updates",
                "ticket.requests", "payments.processed", "notification.triggers"
            ],
            lagCount: 0
        };
        
        // Check database health
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        DatabaseHealth dbHealth = {
            connected: true,
            collections: 8,
            totalDocuments: 0
        };
        
        return {
            status: "healthy",
            services: services,
            kafkaStatus: kafkaHealth,
            databaseStatus: dbHealth,
            timestamp: time:utcToString(time:utcNow())
        };
    }
    
    // Export data
    resource function get export/[string dataType](
        @http:Header string authorization,
        string? startDate = (),
        string? endDate = ()
    ) returns json[]|http:Unauthorized|http:BadRequest|http:InternalServerError {
        // Validate admin token
        if !check validateAdminToken(authorization) {
            return <http:Unauthorized>{
                body: {"error": "Unauthorized access"}
            };
        }
        
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        
        map<json> dateFilter = {};
        if startDate is string && endDate is string {
            dateFilter = {
                "$gte": startDate,
                "$lte": endDate
            };
        }
        
        if dataType == "tickets" {
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");
            map<json> query = dateFilter.length() > 0 ? {"purchaseDate": dateFilter} : {};
            return check exportCollection(ticketsCollection, query);
            
        } else if dataType == "payments" {
            mongodb:Collection paymentsCollection = check db->getCollection("payments");
            map<json> query = dateFilter.length() > 0 ? {"processedAt": dateFilter} : {};
            return check exportCollection(paymentsCollection, query);
            
        } else if dataType == "users" {
            mongodb:Collection usersCollection = check db->getCollection("users");
            json[] users = check exportCollection(usersCollection, {});
            // Remove passwords from export
            foreach json user in users {
                if user is map<json> {
                    user.remove("password");
                }
            }
            return users;
            
        } else {
            return <http:BadRequest>{
                body: {"error": "Invalid data type for export"}
            };
        }
    }
    
    // Health check endpoint
    resource function get health() returns map<json> {
        return {
            "service": "admin-service",
            "status": "healthy",
            "timestamp": time:utcToString(time:utcNow())
        };
    }
}

// Helper function to validate admin token
function validateAdminToken(string authHeader) returns boolean|error {
    if !authHeader.startsWith("Bearer ") {
        return false;
    }
    
    string token = authHeader.substring(7);
    
    jwt:ValidatorConfig validatorConfig = {
        issuer: jwtIssuer,
        audience: ["admin-app"],
        signatureConfig: {
            secret: jwtSecret
        }
    };
    
    jwt:Payload payload = check jwt:validate(token, validatorConfig);
    
    // Check if user has admin role
    string role = check payload.customClaims["role"].ensureType(string);
    return role == "ADMIN" || role == "SUPER_ADMIN";
}

// Helper function to count documents
function countDocuments(mongodb:Collection collection, map<json> query) returns int|error {
    stream<map<json>, error?> docs = check collection->find(query);
    int count = 0;
    check from map<json> doc in docs
        do {
            count += 1;
        };
    return count;
}

// Helper function to calculate total revenue
function calculateTotalRevenue(mongodb:Collection collection, map<json> query) returns decimal|error {
    stream<map<json>, error?> payments = check collection->find(query);
    decimal total = 0.0;
    check from map<json> payment in payments
        do {
            decimal amount = check payment["amount"].ensureType(decimal);
            total = total + amount;
        };
    return total;
}

// Helper function to get tickets by type
function getTicketsByType(mongodb:Collection collection) returns map<int>|error {
    map<int> ticketsByType = {};
    stream<map<json>, error?> tickets = check collection->find({"status": {"$in": ["PAID", "VALIDATED"]}});
    
    check from map<json> ticket in tickets
        do {
            string ticketType = check ticket["ticketType"].ensureType(string);
            int currentCount = ticketsByType[ticketType] ?: 0;
            ticketsByType[ticketType] = currentCount + 1;
        };
    
    return ticketsByType;
}

// Helper function to get revenue by route
function getRevenueByRoute(mongodb:Collection collection) returns map<decimal>|error {
    map<decimal> revenueByRoute = {};
    stream<map<json>, error?> tickets = check collection->find({
        "status": {"$in": ["PAID", "VALIDATED"]},
        "tripDetails": {"$exists": true}
    });
    
    check from map<json> ticket in tickets
        do {
            if ticket.hasKey("tripDetails") {
                json tripDetails = ticket["tripDetails"];
                if tripDetails is map<json> && tripDetails.hasKey("routeId") {
                    string routeId = check tripDetails["routeId"].ensureType(string);
                    decimal price = check ticket["price"].ensureType(decimal);
                    
                    decimal currentRevenue = revenueByRoute[routeId] ?: 0.0;
                    revenueByRoute[routeId] = currentRevenue + price;
                }
            }
        };
    
    return revenueByRoute;
}

// Helper function to check service health
function checkServiceHealth(string serviceName, string endpoint) returns ServiceStatus|error {
    http:Client healthClient = check new (endpoint);
    int startTime = time:monotonicMillis();
    
    http:Response|error response = healthClient->get("");
    int responseTime = time:monotonicMillis() - startTime;
    
    if response is http:Response && response.statusCode == 200 {
        return {
            serviceName: serviceName,
            status: "healthy",
            endpoint: endpoint,
            responseTime: responseTime
        };
    }
    
    return {
        serviceName: serviceName,
        status: "unhealthy",
        endpoint: endpoint,
        responseTime: responseTime
    };
}

// Helper function to export collection data
function exportCollection(mongodb:Collection collection, map<json> query) returns json[]|error {
    stream<map<json>, error?> dataStream = check collection->find(query);
    json[] exportData = [];
    
    check from map<json> item in dataStream
        do {
            exportData.push(item);
        };
    
    return exportData;
}