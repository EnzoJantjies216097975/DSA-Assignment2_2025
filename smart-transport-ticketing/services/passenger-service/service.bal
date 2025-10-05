import ballerina/http;
import ballerina/log;
import ballerina/crypto;
import ballerina/jwt;
import ballerina/uuid;
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
    clientId: "passenger-service",
    acks: "all",
    retryCount: 3
});

// Define user record types
type User record {
    string id?;
    string username;
    string email;
    string password;
    string role;
    string fullName;
    string phoneNumber?;
    decimal accountBalance;
    NotificationPreferences notifications;
    string createdAt?;
    string updatedAt?;
};

type NotificationPreferences record {
    boolean email = true;
    boolean sms = false;
    boolean push = true;
};

type LoginRequest record {
    string username;
    string password;
};

type RegisterRequest record {
    string username;
    string email;
    string password;
    string fullName;
    string phoneNumber?;
};

type AuthResponse record {
    string token;
    User user;
};

type Ticket record {
    string ticketId;
    string userId;
    string ticketType;
    string status;
    decimal price;
    string purchaseDate;
    string validFrom;
    string validUntil;
    TripDetails tripDetails?;
};

type TripDetails record {
    string tripId;
    string routeId;
    string boardingStop;
    string destinationStop;
};

// Service definition
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
service /passenger on new http:Listener(8081) {
    
    // User registration endpoint
    resource function post register(@http:Payload RegisterRequest request) returns AuthResponse|http:BadRequest|http:InternalServerError {
        // Validate input
        if request.username.length() < 3 || request.password.length() < 6 {
            return <http:BadRequest>{
                body: {
                    "error": "Username must be at least 3 characters and password at least 6 characters"
                }
            };
        }
        
        // Check if user already exists
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        map<json> existingUserQuery = {"username": request.username};
        stream<User, error?> existingUsers = check usersCollection->find(existingUserQuery);
        
        User|error? existingUser = existingUsers.next();
        if existingUser is User {
            return <http:BadRequest>{
                body: {"error": "Username already exists"}
            };
        }
        
        // Hash password
        byte[] hashedPassword = crypto:hashSha256(request.password.toBytes());
        string hashedPasswordStr = hashedPassword.toBase64();
        
        // Create new user
        string userId = uuid:createType1AsString();
        string currentTime = time:utcToString(time:utcNow());
        
        User newUser = {
            id: userId,
            username: request.username,
            email: request.email,
            password: hashedPasswordStr,
            role: "PASSENGER",
            fullName: request.fullName,
            phoneNumber: request.phoneNumber,
            accountBalance: 0.0,
            notifications: {},
            createdAt: currentTime,
            updatedAt: currentTime
        };
        
        // Insert user into database
        check usersCollection->insertOne(newUser);
        
        // Publish user registration event to Kafka
        kafka:ProducerRecord userRegisteredEvent = {
            topic: "user.events",
            key: userId.toBytes(),
            value: {
                "eventType": "USER_REGISTERED",
                "userId": userId,
                "username": request.username,
                "email": request.email,
                "timestamp": currentTime
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(userRegisteredEvent);
        
        // Generate JWT token
        jwt:IssuerConfig issuerConfig = {
            issuer: jwtIssuer,
            audience: ["passenger-app"],
            expTime: 86400, // 24 hours
            signatureConfig: {
                algorithm: jwt:HS256,
                secret: jwtSecret
            },
            customClaims: {
                "userId": userId,
                "username": request.username,
                "role": "PASSENGER"
            }
        };
        
        string jwtToken = check jwt:issue(issuerConfig);
        
        // Remove password from response
        newUser.password = "";
        
        return {
            token: jwtToken,
            user: newUser
        };
    }
    
    // User login endpoint
    resource function post login(@http:Payload LoginRequest request) returns AuthResponse|http:Unauthorized|http:InternalServerError {
        // Find user by username
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        map<json> query = {"username": request.username};
        stream<User, error?> users = check usersCollection->find(query);
        
        User|error? user = users.next();
        if user is () || user is error {
            return <http:Unauthorized>{
                body: {"error": "Invalid credentials"}
            };
        }
        
        // Verify password
        byte[] hashedPassword = crypto:hashSha256(request.password.toBytes());
        string hashedPasswordStr = hashedPassword.toBase64();
        
        if user.password != hashedPasswordStr {
            return <http:Unauthorized>{
                body: {"error": "Invalid credentials"}
            };
        }
        
        // Generate JWT token
        jwt:IssuerConfig issuerConfig = {
            issuer: jwtIssuer,
            audience: ["passenger-app"],
            expTime: 86400, // 24 hours
            signatureConfig: {
                algorithm: jwt:HS256,
                secret: jwtSecret
            },
            customClaims: {
                "userId": user.id ?: "",
                "username": user.username,
                "role": user.role
            }
        };
        
        string jwtToken = check jwt:issue(issuerConfig);
        
        // Remove password from response
        user.password = "";
        
        // Publish login event
        kafka:ProducerRecord loginEvent = {
            topic: "user.events",
            key: (user.id ?: "").toBytes(),
            value: {
                "eventType": "USER_LOGIN",
                "userId": user.id ?: "",
                "username": user.username,
                "timestamp": time:utcToString(time:utcNow())
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(loginEvent);
        
        return {
            token: jwtToken,
            user: user
        };
    }
    
    // Get user profile endpoint
    resource function get profile(@http:Header string authorization) returns User|http:Unauthorized|http:InternalServerError {
        // Validate JWT token
        string? userId = check validateTokenAndGetUserId(authorization);
        if userId is () {
            return <http:Unauthorized>{
                body: {"error": "Invalid or expired token"}
            };
        }
        
        // Fetch user from database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        map<json> query = {"id": userId};
        stream<User, error?> users = check usersCollection->find(query);
        
        User|error? user = users.next();
        if user is () || user is error {
            return <http:Unauthorized>{
                body: {"error": "User not found"}
            };
        }
        
        // Remove password from response
        user.password = "";
        
        return user;
    }
    
    // Update user profile endpoint
    resource function put profile(@http:Header string authorization, @http:Payload User updateData) 
            returns User|http:Unauthorized|http:InternalServerError {
        // Validate JWT token
        string? userId = check validateTokenAndGetUserId(authorization);
        if userId is () {
            return <http:Unauthorized>{
                body: {"error": "Invalid or expired token"}
            };
        }
        
        // Update user in database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        // Prepare update document
        map<json> filter = {"id": userId};
        map<json> update = {
            "$set": {
                "fullName": updateData.fullName,
                "email": updateData.email,
                "phoneNumber": updateData.phoneNumber,
                "notifications": updateData.notifications,
                "updatedAt": time:utcToString(time:utcNow())
            }
        };
        
        mongodb:UpdateResult updateResult = check usersCollection->updateOne(filter, update);
        
        // Fetch updated user
        stream<User, error?> users = check usersCollection->find(filter);
        User|error? updatedUser = users.next();
        
        if updatedUser is User {
            updatedUser.password = "";
            return updatedUser;
        }
        
        return <http:InternalServerError>{
            body: {"error": "Failed to update profile"}
        };
    }
    
    // Get user's tickets endpoint
    resource function get tickets(@http:Header string authorization) returns Ticket[]|http:Unauthorized|http:InternalServerError {
        // Validate JWT token
        string? userId = check validateTokenAndGetUserId(authorization);
        if userId is () {
            return <http:Unauthorized>{
                body: {"error": "Invalid or expired token"}
            };
        }
        
        // Fetch tickets from database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        
        map<json> query = {
            "userId": userId,
            "status": {"$in": ["PAID", "VALIDATED"]}
        };
        
        stream<Ticket, error?> ticketsStream = check ticketsCollection->find(query);
        
        Ticket[] tickets = [];
        check from Ticket ticket in ticketsStream
            do {
                tickets.push(ticket);
            };
        
        return tickets;
    }
    
    // Get user's account balance
    resource function get balance(@http:Header string authorization) returns map<json>|http:Unauthorized|http:InternalServerError {
        // Validate JWT token
        string? userId = check validateTokenAndGetUserId(authorization);
        if userId is () {
            return <http:Unauthorized>{
                body: {"error": "Invalid or expired token"}
            };
        }
        
        // Fetch user from database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        map<json> query = {"id": userId};
        stream<User, error?> users = check usersCollection->find(query);
        
        User|error? user = users.next();
        if user is User {
            return {
                "balance": user.accountBalance,
                "currency": "NAD"
            };
        }
        
        return <http:InternalServerError>{
            body: {"error": "Failed to get balance"}
        };
    }
    
    // Top up account balance endpoint
    resource function post topup(@http:Header string authorization, @http:Payload map<json> request) 
            returns map<json>|http:BadRequest|http:Unauthorized|http:InternalServerError {
        // Validate JWT token
        string? userId = check validateTokenAndGetUserId(authorization);
        if userId is () {
            return <http:Unauthorized>{
                body: {"error": "Invalid or expired token"}
            };
        }
        
        // Validate amount
        decimal amount = check request["amount"].ensureType();
        if amount <= 0 {
            return <http:BadRequest>{
                body: {"error": "Amount must be greater than 0"}
            };
        }
        
        // Update balance in database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        map<json> filter = {"id": userId};
        map<json> update = {
            "$inc": {"accountBalance": amount},
            "$set": {"updatedAt": time:utcToString(time:utcNow())}
        };
        
        mongodb:UpdateResult updateResult = check usersCollection->updateOne(filter, update);
        
        // Publish top-up event to Kafka
        kafka:ProducerRecord topUpEvent = {
            topic: "payment.events",
            key: userId.toBytes(),
            value: {
                "eventType": "ACCOUNT_TOP_UP",
                "userId": userId,
                "amount": amount,
                "timestamp": time:utcToString(time:utcNow())
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(topUpEvent);
        
        // Fetch updated balance
        stream<User, error?> users = check usersCollection->find(filter);
        User|error? user = users.next();
        
        if user is User {
            return {
                "newBalance": user.accountBalance,
                "currency": "NAD",
                "message": "Account topped up successfully"
            };
        }
        
        return <http:InternalServerError>{
            body: {"error": "Failed to top up account"}
        };
    }
    
    // Update notification preferences
    resource function put notifications(@http:Header string authorization, @http:Payload NotificationPreferences preferences) 
            returns map<json>|http:Unauthorized|http:InternalServerError {
        // Validate JWT token
        string? userId = check validateTokenAndGetUserId(authorization);
        if userId is () {
            return <http:Unauthorized>{
                body: {"error": "Invalid or expired token"}
            };
        }
        
        // Update preferences in database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection usersCollection = check db->getCollection("users");
        
        map<json> filter = {"id": userId};
        map<json> update = {
            "$set": {
                "notifications": preferences,
                "updatedAt": time:utcToString(time:utcNow())
            }
        };
        
        mongodb:UpdateResult updateResult = check usersCollection->updateOne(filter, update);
        
        return {
            "message": "Notification preferences updated successfully",
            "preferences": preferences
        };
    }
}

// Helper function to validate JWT token and extract user ID
function validateTokenAndGetUserId(string authHeader) returns string?|error {
    if !authHeader.startsWith("Bearer ") {
        return ();
    }
    
    string token = authHeader.substring(7);
    
    jwt:ValidatorConfig validatorConfig = {
        issuer: jwtIssuer,
        audience: ["passenger-app"],
        signatureConfig: {
            secret: jwtSecret
        }
    };
    
    jwt:Payload payload = check jwt:validate(token, validatorConfig);
    
    return payload.customClaims["userId"].toString();
}