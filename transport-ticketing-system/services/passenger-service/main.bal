import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/mongodb;
import ballerina/crypto;

// MongoDB configuration
configurable string mongoHost = "mongodb";
configurable int mongoPort = 27017;
configurable string mongoUsername = "admin";
configurable string mongoPassword = "password123";
configurable string mongoDatabase = "transport_db";

// MongoDB client
final mongodb:Client mongoClient = check new ({
    connection: {
        serverAddress: {
            host: mongoHost,
            port: mongoPort
        },
        auth: <mongodb:ScramSha256AuthCredential>{
            username: mongoUsername,
            password: mongoPassword,
            database: "admin"
        }
    }
});

// User types
public type User record {|
    string id;
    string email;
    string passwordHash;
    string firstName;
    string lastName;
    string phone;
    string role;
    string createdAt;
    string updatedAt?;
|};

public type RegisterRequest record {|
    string email;
    string password;
    string firstName;
    string lastName;
    string phone;
|};

public type LoginRequest record {|
    string email;
    string password;
|};

public type LoginResponse record {|
    string message;
    string userId;
    string email;
    string firstName;
    string lastName;
|};

public type ErrorResponse record {|
    string message;
    string timestamp;
|};

// Service implementation
service /passenger on new http:Listener(9090) {
    
    // Health check endpoint
    resource function get health() returns string {
        return "Passenger Service is running";
    }

    // Register new passenger
    resource function post register(RegisterRequest request) returns http:Created|http:BadRequest|http:InternalServerError {
        do {
            // Validate input
            if request.email.trim() == "" || request.password.trim() == "" {
                return <http:BadRequest>{
                    body: {
                        message: "Email and password are required",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection usersCollection = check db->getCollection("users");

            // Check if user already exists
            map<json> existingUserQuery = {
                "email": request.email
            };
            stream<User, error?> existingUsers = check usersCollection->find(existingUserQuery);
            User[]|error userArray = from User user in existingUsers select user;
            
            if userArray is User[] && userArray.length() > 0 {
                return <http:BadRequest>{
                    body: {
                        message: "User with this email already exists",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

            // Hash password (simple SHA-256 for demo - use bcrypt in production)
            byte[] passwordBytes = request.password.toBytes();
            byte[] hashedPassword = crypto:hashSha256(passwordBytes);
            string passwordHash = hashedPassword.toBase16();

            // Create new user
            string userId = uuid:createType1AsString();
            string currentTime = time:utcToString(time:utcNow());
            
            User newUser = {
                id: userId,
                email: request.email,
                passwordHash: passwordHash,
                firstName: request.firstName,
                lastName: request.lastName,
                phone: request.phone,
                role: "PASSENGER",
                createdAt: currentTime
            };

            check usersCollection->insertOne(newUser);
            
            log:printInfo(string `New user registered: ${request.email}`);
            
            return <http:Created>{
                body: {
                    message: "User registered successfully",
                    userId: userId,
                    email: request.email
                }
            };

        } on fail error e {
            log:printError("Error registering user", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to register user",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Login passenger
    resource function post login(LoginRequest request) returns LoginResponse|http:Unauthorized|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection usersCollection = check db->getCollection("users");

            // Hash the provided password
            byte[] passwordBytes = request.password.toBytes();
            byte[] hashedPassword = crypto:hashSha256(passwordBytes);
            string passwordHash = hashedPassword.toBase16();

            // Find user by email and password
            map<json> query = {
                "email": request.email,
                "passwordHash": passwordHash
            };
            
            stream<User, error?> users = check usersCollection->find(query);
            User[]|error userArray = from User user in users select user;
            
            if userArray is User[] && userArray.length() > 0 {
                User user = userArray[0];
                log:printInfo(string `User logged in: ${user.email}`);
                
                return {
                    message: "Login successful",
                    userId: user.id,
                    email: user.email,
                    firstName: user.firstName,
                    lastName: user.lastName
                };
            } else {
                return <http:Unauthorized>{
                    body: {
                        message: "Invalid email or password",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

        } on fail error e {
            log:printError("Error during login", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Login failed",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get user profile
    resource function get profile/[string userId]() returns User|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection usersCollection = check db->getCollection("users");

            map<json> query = {"id": userId};
            stream<User, error?> users = check usersCollection->find(query);
            User[]|error userArray = from User user in users select user;
            
            if userArray is User[] && userArray.length() > 0 {
                return userArray[0];
            } else {
                return <http:NotFound>{
                    body: {
                        message: "User not found",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

        } on fail error e {
            log:printError("Error fetching user profile", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to fetch user profile",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }
}