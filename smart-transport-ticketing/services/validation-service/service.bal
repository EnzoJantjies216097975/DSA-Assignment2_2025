import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerina/os;
import ballerinax/kafka;
import ballerinax/mongodb;

// Configuration for MongoDB connection
configurable string mongoHost = os:getEnv("MONGO_HOST") ?: "localhost";
configurable int mongoPort = check int:fromString(os:getEnv("MONGO_PORT") ?: "27017");
configurable string databaseName = os:getEnv("MONGO_DATABASE") ?: "transport_db";

string mongodbUrl = string `mongodb://${mongoHost}:${mongoPort}`;

// Configuration for Kafka
configurable string kafkaBootstrapServers = os:getEnv("KAFKA_BOOTSTRAP_SERVERS") ?: "localhost:9092";

// MongoDB client for database operations
mongodb:Client mongoClient = check new (mongodbUrl);

// Kafka producer for publishing events
kafka:Producer kafkaProducer = check new ({
    bootstrapServers: kafkaBootstrapServers,
    clientId: "validation-service",
    acks: "all",
    retryCount: 3
});

// Define validation-related record types
type ValidationRequest record {
    string ticketId;
    string validatorId;
    string validatorName?;
    string vehicleId;
    string tripId;
    string routeId;
    DeviceInfo deviceInfo?;
    Location location;
};

type DeviceInfo record {
    string deviceId;
    string deviceType;
    string osVersion?;
};

type Location record {
    decimal latitude;
    decimal longitude;
    string stopName?;
};

type ValidationResult record {
    string validationId;
    string ticketId;
    boolean success;
    string status;
    string message;
    TicketDetails ticketDetails?;
    string failureReason?;
    int ridesRemainingAfter?;
    string validatedAt;
};

type TicketDetails record {
    string ticketType;
    string userId;
    string status;
    string validUntil;
    int ridesRemaining?;
};

type ValidationHistory record {
    string validationId;
    string ticketId;
    string userId;
    string validatorId;
    string vehicleId;
    string tripId;
    boolean success;
    string validatedAt;
    Location location;
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

service /validation on new http:Listener(8087) {
    
    // Validate a ticket
    resource function post validate(@http:Payload ValidationRequest request) 
            returns ValidationResult|http:BadRequest|http:InternalServerError {
        
        log:printInfo("Validation request received for ticket: " + request.ticketId);
        
        // Generate validation ID
        string validationId = "VAL-" + uuid:createType1AsString().substring(0, 12).toUpperAscii();
        string currentTime = time:utcToString(time:utcNow());
        
        // Fetch ticket from database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        
        map<json> query = {"ticketId": request.ticketId};
        stream<map<json>, error?> ticketsStream = check ticketsCollection->find(query);
        
        map<json>|error? ticket = ticketsStream.next();
        if ticket is () || ticket is error {
            log:printWarn("Ticket not found: " + request.ticketId);
            
            // Record failed validation attempt
            check recordValidation(validationId, request, false, "TICKET_NOT_FOUND");
            
            return {
                validationId: validationId,
                ticketId: request.ticketId,
                success: false,
                status: "INVALID",
                message: "Ticket not found",
                failureReason: "Ticket ID does not exist in the system",
                validatedAt: currentTime
            };
        }
        
        // Check ticket status
        string ticketStatus = check ticket["status"].ensureType(string);
        string userId = check ticket["userId"].ensureType(string);
        string ticketType = check ticket["ticketType"].ensureType(string);
        string validUntil = check ticket["validUntil"].ensureType(string);
        
        // Validate ticket status
        if ticketStatus == "CREATED" || ticketStatus == "PENDING_PAYMENT") {
            check recordValidation(validationId, request, false, "PAYMENT_PENDING");
            
            return {
                validationId: validationId,
                ticketId: request.ticketId,
                success: false,
                status: "PAYMENT_PENDING",
                message: "Ticket payment is pending",
                failureReason: "Ticket must be paid before validation",
                ticketDetails: {
                    ticketType: ticketType,
                    userId: userId,
                    status: ticketStatus,
                    validUntil: validUntil
                },
                validatedAt: currentTime
            };
        }
        
        if ticketStatus == "CANCELLED" || ticketStatus == "EXPIRED") {
            check recordValidation(validationId, request, false, ticketStatus);
            
            return {
                validationId: validationId,
                ticketId: request.ticketId,
                success: false,
                status: ticketStatus,
                message: "Ticket is " + ticketStatus.toLowerAscii(),
                failureReason: "Ticket has been " + ticketStatus.toLowerAscii(),
                ticketDetails: {
                    ticketType: ticketType,
                    userId: userId,
                    status: ticketStatus,
                    validUntil: validUntil
                },
                validatedAt: currentTime
            };
        }
        
        // Check validity period
        time:Utc currentUtcTime = time:utcNow();
        time:Utc|error validUntilTime = time:utcFromString(validUntil);
        
        if validUntilTime is time:Utc {
            if time:utcDiffSeconds(validUntilTime, currentUtcTime) < 0 {
                // Ticket has expired
                check updateTicketStatus(request.ticketId, "EXPIRED");
                check recordValidation(validationId, request, false, "EXPIRED");
                
                return {
                    validationId: validationId,
                    ticketId: request.ticketId,
                    success: false,
                    status: "EXPIRED",
                    message: "Ticket has expired",
                    failureReason: "Ticket validity period has passed",
                    ticketDetails: {
                        ticketType: ticketType,
                        userId: userId,
                        status: "EXPIRED",
                        validUntil: validUntil
                    },
                    validatedAt: currentTime
                };
            }
        }
        
        // Check for single-use tickets
        if ticketType == "SINGLE" || ticketType == "SINGLE_RIDE") {
            // Check if already validated
            json validationHistory = ticket["validationHistory"];
            if validationHistory is json[] && validationHistory.length() > 0 {
                check recordValidation(validationId, request, false, "ALREADY_USED");
                
                return {
                    validationId: validationId,
                    ticketId: request.ticketId,
                    success: false,
                    status: "ALREADY_USED",
                    message: "Single-use ticket has already been used",
                    failureReason: "This ticket can only be used once",
                    ticketDetails: {
                        ticketType: ticketType,
                        userId: userId,
                        status: ticketStatus,
                        validUntil: validUntil
                    },
                    validatedAt: currentTime
                };
            }
        }
        
        // Check multi-ride tickets
        int ridesRemaining = 0;
        if ticketType == "MULTI_RIDE" {
            json ridesRemainingJson = ticket["ridesRemaining"];
            if ridesRemainingJson is int {
                ridesRemaining = ridesRemainingJson;
                if ridesRemaining <= 0 {
                    check recordValidation(validationId, request, false, "NO_RIDES_REMAINING");
                    
                    return {
                        validationId: validationId,
                        ticketId: request.ticketId,
                        success: false,
                        status: "NO_RIDES_REMAINING",
                        message: "No rides remaining on this ticket",
                        failureReason: "All rides have been used",
                        ticketDetails: {
                            ticketType: ticketType,
                            userId: userId,
                            status: ticketStatus,
                            validUntil: validUntil,
                            ridesRemaining: 0
                        },
                        validatedAt: currentTime
                    };
                }
            }
        }
        
        // Validation successful - update ticket
        ValidationHistory validationRecord = {
            validationId: validationId,
            ticketId: request.ticketId,
            userId: userId,
            validatorId: request.validatorId,
            vehicleId: request.vehicleId,
            tripId: request.tripId,
            success: true,
            validatedAt: currentTime,
            location: request.location
        };
        
        // Update ticket in database
        map<json> updateData = {
            "$push": {
                "validationHistory": validationRecord
            },
            "$set": {
                "lastValidatedAt": currentTime,
                "updatedAt": currentTime
            }
        };
        
        // For single-use tickets, mark as validated
        if ticketType == "SINGLE" || ticketType == "SINGLE_RIDE") {
            updateData["$set"]["status"] = "VALIDATED";
        }
        
        // For multi-ride tickets, decrement rides remaining
        if ticketType == "MULTI_RIDE" && ridesRemaining > 0 {
            updateData["$inc"] = {"ridesRemaining": -1};
            ridesRemaining = ridesRemaining - 1;
        }
        
        mongodb:UpdateResult updateResult = check ticketsCollection->updateOne(query, updateData);
        
        // Record successful validation
        check recordValidation(validationId, request, true, "SUCCESS");
        
        // Publish validation event to Kafka
        kafka:ProducerRecord validationEvent = {
            topic: "ticket.validations",
            key: request.ticketId.toBytes(),
            value: {
                "eventType": "TICKET_VALIDATED",
                "validationId": validationId,
                "ticketId": request.ticketId,
                "userId": userId,
                "validatorId": request.validatorId,
                "vehicleId": request.vehicleId,
                "tripId": request.tripId,
                "routeId": request.routeId,
                "location": request.location,
                "success": true,
                "timestamp": currentTime
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(validationEvent);
        
        log:printInfo("Ticket validated successfully: " + request.ticketId);
        
        return {
            validationId: validationId,
            ticketId: request.ticketId,
            success: true,
            status: "VALID",
            message: "Ticket validated successfully",
            ticketDetails: {
                ticketType: ticketType,
                userId: userId,
                status: ticketStatus,
                validUntil: validUntil,
                ridesRemaining: ticketType == "MULTI_RIDE" ? ridesRemaining : ()
            },
            ridesRemainingAfter: ticketType == "MULTI_RIDE" ? ridesRemaining : (),
            validatedAt: currentTime
        };
    }
    
    // Get validation history for a ticket
    resource function get tickets/[string ticketId]/validations() 
            returns ValidationHistory[]|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection validationsCollection = check db->getCollection("validations");
        
        map<json> query = {"ticketId": ticketId};
        stream<ValidationHistory, error?> validationsStream = check validationsCollection->find(query);
        
        ValidationHistory[] validations = [];
        check from ValidationHistory validation in validationsStream
            do {
                validations.push(validation);
            };
        
        return validations;
    }
    
    // Get validations by validator
    resource function get validators/[string validatorId]/validations(string? date = ()) 
            returns ValidationHistory[]|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection validationsCollection = check db->getCollection("validations");
        
        map<json> query = {"validatorId": validatorId};
        if date is string {
            string startOfDay = date + "T00:00:00Z";
            string endOfDay = date + "T23:59:59Z";
            query["validatedAt"] = {
                "$gte": startOfDay,
                "$lte": endOfDay
            };
        }
        
        stream<ValidationHistory, error?> validationsStream = check validationsCollection->find(query);
        
        ValidationHistory[] validations = [];
        check from ValidationHistory validation in validationsStream
            do {
                validations.push(validation);
            };
        
        return validations;
    }
    
    // Get validation statistics
    resource function get statistics(string? startDate = (), string? endDate = ()) 
            returns map<json>|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection validationsCollection = check db->getCollection("validations");
        
        map<json> query = {};
        if startDate is string && endDate is string {
            query["validatedAt"] = {
                "$gte": startDate,
                "$lte": endDate
            };
        }
        
        stream<ValidationHistory, error?> validationsStream = check validationsCollection->find(query);
        
        int totalValidations = 0;
        int successfulValidations = 0;
        int failedValidations = 0;
        map<int> validationsByValidator = {};
        map<int> validationsByRoute = {};
        
        check from ValidationHistory validation in validationsStream
            do {
                totalValidations += 1;
                if validation.success {
                    successfulValidations += 1;
                } else {
                    failedValidations += 1;
                }
                
                // Count by validator
                int currentValidatorCount = validationsByValidator[validation.validatorId] ?: 0;
                validationsByValidator[validation.validatorId] = currentValidatorCount + 1;
            };
        
        return {
            "totalValidations": totalValidations,
            "successfulValidations": successfulValidations,
            "failedValidations": failedValidations,
            "successRate": totalValidations > 0 ? 
                (<decimal>successfulValidations / <decimal>totalValidations * 100.0) : 0.0,
            "validationsByValidator": validationsByValidator,
            "period": {
                "startDate": startDate ?: "all-time",
                "endDate": endDate ?: "all-time"
            }
        };
    }
    
    // Health check endpoint
    resource function get health() returns map<json> {
        return {
            "service": "validation-service",
            "status": "healthy",
            "timestamp": time:utcToString(time:utcNow())
        };
    }
}

// Helper function to record validation in database
function recordValidation(string validationId, ValidationRequest request, 
                          boolean success, string status) returns error? {
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection validationsCollection = check db->getCollection("validations");
    
    map<json> validationRecord = {
        "validationId": validationId,
        "ticketId": request.ticketId,
        "validatorId": request.validatorId,
        "validatorName": request.validatorName,
        "vehicleId": request.vehicleId,
        "tripId": request.tripId,
        "routeId": request.routeId,
        "success": success,
        "failureReason": !success ? status : (),
        "location": request.location,
        "deviceInfo": request.deviceInfo,
        "validatedAt": time:utcToString(time:utcNow()),
        "createdAt": time:utcToString(time:utcNow())
    };
    
    check validationsCollection->insertOne(validationRecord);
}

// Helper function to update ticket status
function updateTicketStatus(string ticketId, string newStatus) returns error? {
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection ticketsCollection = check db->getCollection("tickets");
    
    map<json> filter = {"ticketId": ticketId};
    map<json> update = {
        "$set": {
            "status": newStatus,
            "updatedAt": time:utcToString(time:utcNow())
        }
    };
    
    mongodb:UpdateResult result = check ticketsCollection->updateOne(filter, update);
}