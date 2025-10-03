import ballerina/io;
import ballerina/http;
import ballerina/log;
import ballerina/crypto;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;

configurable string mongoHost = "mongodb"; // Docker service name
configurable int mongoPort = 27017;
configurable string dbName = "transport_ticketing";
configurable kafkaBootstrapServers = "kafka:9092";

// Initialize MongoDB client
mongodb:Client mongoClient = check new ({
    connection: {
        host: mongoHost,
        port: mongoPort,
        auth: {
            username: "",
            password: ""
        },
        options: {
            sslEnabled: false,
            serverSelectionTimeout: 5000
        }
    }
});

// Initialize Kafka producer for publishing events
kafka:Producer kafkaProducer = check new ({
    bootstrapServers: kafkaBootstrapServers,
    clientId: "passenger-service-producer",
    acks: "all",
    compressionType: "snappy",
    retryCount: 3
});

type User record {
    string userId;
    string email;
    string password;  // This will be hashed, never stored in plain text
    string name;
    string role;  // PASSENGER, ADMIN, or VALIDATOR
    time:Utc createdAt;
    decimal balance;  // Money in the user's account for ticket purchases
    string[] activeTickets;  // Array of ticket IDs this user currently holds
};

type RegistrationRequest record {
    string email;
    string password;
    string name;
};

type LoginRequest record {
    string email;
    string password;
};

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],  // In production, specify exact origins
        allowMethods: ["GET", "POST", "PUT", "DELETE"],
        allowHeaders: ["Content-Type", "Authorization"]
    }
}
service /passenger on new http:Listener(8080) {
    resource function get health() returns http:Response {
        http:Response response = new;
        response.statusCode = 200;
        response.setJsonPayload({
            status: "healthy",
            service: "passenger-service",
            timestamp: time:utcNow().toString()
        });
        return response;
    }

     resource function post register(@http:Payload RegistrationRequest request) 
            returns http:Response|error {
        
        log:printInfo("Registering new user: " + request.email);

         string userId = "USR_" + time:utcNow()[0].toString();

        byte[] hashedPassword = crypto:hashSha256(request.password.toBytes());
        string hashedPasswordStr = hashedPassword.toBase16();

        // Create the user object
        User newUser = {
            userId: userId,
            email: request.email,
            password: hashedPasswordStr,
            name: request.name,
            role: "PASSENGER",  // Default role for new registrations
            createdAt: time:utcNow(),
            balance: 0.0,  // Start with no money in account
            activeTickets: []  // No tickets initially
        };

        mongodb:Database db = check mongoClient->getDatabase(dbName);
        mongodb:Collection users = check db->getCollection("users");

        mongodb:Error? insertResult = users->insertOne(newUser);
        if (insertResult is mongodb:Error) {
            log:printError("Failed to register user", 'error = insertResult);

            // Return an error response to the client
            http:Response response = new;
            response.statusCode = 400;
            response.setJsonPayload({
                error: "Registration failed. Email might already exist."
            });
            return response;
        }

        kafka:Error? sendResult = kafkaProducer->send({
            topic: "notifications.send",
            value: {
                type: "USER_REGISTERED",
                userId: userId,
                email: request.email,
                name: request.name,
                timestamp: time:utcNow().toString()
            }.toString()
        });
        
        if (sendResult is kafka:Error) {
            log:printWarn("Failed to send registration notification", 'error = sendResult);
            // We don't fail the registration if notification fails
        }
        
        // Return success response
        http:Response response = new;
        response.statusCode = 201;  // 201 = Created
        response.setJsonPayload({
            message: "User registered successfully",
            userId: userId
        });
        return response;
    }
    
    // Login endpoint - authenticates user and returns a token
    resource function post login(@http:Payload LoginRequest request) 
            returns http:Response|error {
        
        log:printInfo("Login attempt for: " + request.email);
        
        // Hash the provided password to compare with stored hash
        byte[] hashedPassword = crypto:hashSha256(request.password.toBytes());
        string hashedPasswordStr = hashedPassword.toBase16();
        
        // Find the user in MongoDB
        mongodb:Database db = check mongoClient->getDatabase(dbName);
        mongodb:Collection users = check db->getCollection("users");
        
        // Search for user with matching email and password hash
        stream<User, mongodb:Error?> userStream = check users->find({
            email: request.email,
            password: hashedPasswordStr
        });
        
        User[] userList = check from User user in userStream select user;
        
        if (userList.length() == 0) {
            // User not found or wrong password
            http:Response response = new;
            response.statusCode = 401;  // 401 = Unauthorized
            response.setJsonPayload({error: "Invalid credentials"});
            return response;
        }
        
        User user = userList[0];
        
        // In a real system, you'd generate a JWT token here
        // For simplicity, we'll just return a simple token
        string token = "TOKEN_" + user.userId + "_" + time:utcNow()[0].toString();
        
        http:Response response = new;
        response.statusCode = 200;
        response.setJsonPayload({
            message: "Login successful",
            token: token,
            userId: user.userId,
            name: user.name,
            balance: user.balance
        });
        return response;
    }
    
    // Get user profile - retrieves user information
    resource function get profile/[string userId]() returns http:Response|error {
        log:printInfo("Fetching profile for user: " + userId);
        
        mongodb:Database db = check mongoClient->getDatabase(dbName);
        mongodb:Collection users = check db->getCollection("users");
        
        stream<User, mongodb:Error?> userStream = check users->find({userId: userId});
        User[] userList = check from User user in userStream select user;
        
        if (userList.length() == 0) {
            http:Response response = new;
            response.statusCode = 404;  // 404 = Not Found
            response.setJsonPayload({error: "User not found"});
            return response;
        }
        
        User user = userList[0];
        
        // Don't send the password hash back to the client
        http:Response response = new;
        response.statusCode = 200;
        response.setJsonPayload({
            userId: user.userId,
            email: user.email,
            name: user.name,
            balance: user.balance,
            activeTickets: user.activeTickets,
            createdAt: user.createdAt.toString()
        });
        return response;
    }
    
    // Add money to user's account for ticket purchases
    resource function post balance/add(@http:Payload record {|
        string userId; 
        decimal amount;
    |} request) returns http:Response|error {
        
        log:printInfo("Adding balance for user: " + request.userId + 
                     ", amount: " + request.amount.toString());
        
        if (request.amount <= 0) {
            http:Response response = new;
            response.statusCode = 400;
            response.setJsonPayload({error: "Amount must be positive"});
            return response;
        }
        
        mongodb:Database db = check mongoClient->getDatabase(dbName);
        mongodb:Collection users = check db->getCollection("users");
        
        // Use MongoDB's $inc operator to atomically increment the balance
        // This prevents race conditions if multiple balance updates happen simultaneously
        mongodb:UpdateResult updateResult = check users->updateOne(
            {userId: request.userId},
            {"$inc": {"balance": request.amount}}
        );
        
        if (updateResult.matchedCount == 0) {
            http:Response response = new;
            response.statusCode = 404;
            response.setJsonPayload({error: "User not found"});
            return response;
        }
        
        // Publish balance update event for audit trail
        kafka:Error? sendResult = kafkaProducer->send({
            topic: "notifications.send",
            value: {
                type: "BALANCE_UPDATED",
                userId: request.userId,
                amount: request.amount,
                timestamp: time:utcNow().toString()
            }.toString()
        });
        
        http:Response response = new;
        response.statusCode = 200;
        response.setJsonPayload({
            message: "Balance updated successfully",
            amountAdded: request.amount
        });
        return response;
    }
}