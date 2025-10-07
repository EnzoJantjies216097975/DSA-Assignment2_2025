import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;

// Configuration
configurable string mongoHost = "mongodb";
configurable int mongoPort = 27017;
configurable string mongoUsername = "admin";
configurable string mongoPassword = "password123";
configurable string mongoDatabase = "transport_db";
configurable string kafkaBootstrapServers = "kafka:9092";

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

// Kafka producer
final kafka:Producer kafkaProducer = check new (kafkaBootstrapServers, {
    clientId: "ticketing-service-producer",
    acks: "all",
    retryCount: 3
});

// Kafka consumer for payment events
listener kafka:Listener paymentConsumer = new (kafkaBootstrapServers, {
    groupId: "ticketing-payment-group",
    topics: ["payments.processed"]
});

// Types
public type Ticket record {|
    string id;
    string userId;
    string tripId?;
    string ticketType;
    string status;
    decimal price;
    string purchaseDate;
    string validFrom;
    string validUntil;
    int ridesRemaining?;
    string validatedAt?;
    string validatedBy?;
    string paymentId?;
    string createdAt;
    string updatedAt?;
|};

public type TicketPurchaseRequest record {|
    string userId;
    string tripId?;
    string ticketType;
    string paymentMethod;
|};

public type TicketValidationRequest record {|
    string ticketId;
    string validatorId;
    string tripId?;
|};

public type PaymentProcessedEvent record {|
    string ticketId;
    string userId;
    string paymentId;
    string status;
    decimal amount;
    string timestamp;
|};

public type TicketRequestEvent record {|
    string ticketId;
    string userId;
    string tripId?;
    string ticketType;
    decimal price;
    string timestamp;
|};

public type TicketValidatedEvent record {|
    string ticketId;
    string userId;
    string tripId?;
    string validatedBy;
    string timestamp;
|};

// Helper function to calculate ticket price
function calculateTicketPrice(string ticketType) returns decimal {
    match ticketType {
        "SINGLE_RIDE" => {
            return 15.00;
        }
        "MULTIPLE_RIDE" => {
            return 120.00; // 10 rides
        }
        "DAILY_PASS" => {
            return 50.00;
        }
        "WEEKLY_PASS" => {
            return 300.00;
        }
        "MONTHLY_PASS" => {
            return 1000.00;
        }
        _ => {
            return 15.00;
        }
    }
}

// Helper function to calculate validity period
function calculateValidity(string ticketType) returns [string, string, int?] {
    time:Utc currentTime = time:utcNow();
    string validFrom = time:utcToString(currentTime);
    
    match ticketType {
        "SINGLE_RIDE" => {
            time:Utc validUntilTime = time:utcAddSeconds(currentTime, 86400); // 24 hours
            return [validFrom, time:utcToString(validUntilTime), 1];
        }
        "MULTIPLE_RIDE" => {
            time:Utc validUntilTime = time:utcAddSeconds(currentTime, 2592000); // 30 days
            return [validFrom, time:utcToString(validUntilTime), 10];
        }
        "DAILY_PASS" => {
            time:Utc validUntilTime = time:utcAddSeconds(currentTime, 86400); // 24 hours
            return [validFrom, time:utcToString(validUntilTime), ()];
        }
        "WEEKLY_PASS" => {
            time:Utc validUntilTime = time:utcAddSeconds(currentTime, 604800); // 7 days
            return [validFrom, time:utcToString(validUntilTime), ()];
        }
        "MONTHLY_PASS" => {
            time:Utc validUntilTime = time:utcAddSeconds(currentTime, 2592000); // 30 days
            return [validFrom, time:utcToString(validUntilTime), ()];
        }
        _ => {
            time:Utc validUntilTime = time:utcAddSeconds(currentTime, 86400);
            return [validFrom, time:utcToString(validUntilTime), 1];
        }
    }
}

// Service implementation
service /ticketing on new http:Listener(9092) {
    
    resource function get health() returns string {
        log:printInfo("Ticketing service health check");
        return "Ticketing Service is running";
    }

    // Purchase a ticket - IMPROVED KAFKA PUBLISHING
    resource function post tickets/purchase(TicketPurchaseRequest request) returns http:Created|http:BadRequest|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");

            string ticketId = uuid:createType1AsString();
            string currentTime = time:utcToString(time:utcNow());
            
            decimal price = calculateTicketPrice(request.ticketType);
            [string, string, int?] validity = calculateValidity(request.ticketType);
            
            Ticket newTicket = {
                id: ticketId,
                userId: request.userId,
                tripId: request.tripId,
                ticketType: request.ticketType,
                status: "PAYMENT_PENDING",
                price: price,
                purchaseDate: currentTime,
                validFrom: validity[0],
                validUntil: validity[1],
                ridesRemaining: validity[2],
                createdAt: currentTime
            };

            check ticketsCollection->insertOne(newTicket);
            
            // Publish ticket request event to Kafka with better error handling
            TicketRequestEvent ticketEvent = {
                ticketId: ticketId,
                userId: request.userId,
                tripId: request.tripId,
                ticketType: request.ticketType,
                price: price,
                timestamp: currentTime
            };

            log:printInfo(string `Publishing ticket request to Kafka for ticket: ${ticketId}`);
            
            error? kafkaResult = kafkaProducer->send({
                topic: "ticket.requests",
                value: ticketEvent.toJsonString().toBytes()
            });

            if kafkaResult is error {
                log:printError(string `Failed to publish to Kafka topic 'ticket.requests': ${kafkaResult.message()}`, 'error = kafkaResult);
                // Ticket is created but payment won't be processed automatically
                // Consider implementing a retry mechanism here
            } else {
                log:printInfo(string `Successfully published to Kafka topic 'ticket.requests' for ticket: ${ticketId}`);
            }

            log:printInfo(string `Ticket purchase initiated: ${ticketId}, price: ${price}, type: ${request.ticketType}`);
            
            return <http:Created>{
                body: {
                    message: "Ticket purchase initiated",
                    ticketId: ticketId,
                    price: price,
                    status: "PAYMENT_PENDING"
                }
            };

        } on fail error e {
            log:printError("Error purchasing ticket", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to purchase ticket",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get ticket by ID
    resource function get tickets/[string ticketId]() returns Ticket|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");

            map<json> query = {"id": ticketId};
            stream<record {}, error?> resultStream = check ticketsCollection->find(query);

            Ticket[] tickets = [];
            error? e = resultStream.forEach(function(record {} item) {
                Ticket|error convertedTicket = item.cloneWithType(Ticket);
                if convertedTicket is Ticket {
                    tickets.push(convertedTicket);
                }
            });

            if tickets.length() > 0 {
                return tickets[0];
            } else {
                return <http:NotFound>{
                    body: {
                        message: "Ticket not found",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

        } on fail error e {
            log:printError("Error fetching ticket", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to fetch ticket",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get user's tickets
    resource function get users/[string userId]/tickets() returns Ticket[]|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");

            map<json> query = {"userId": userId};
            stream<record {}, error?> resultStream = check ticketsCollection->find(query);

            Ticket[] tickets = [];
            error? e = resultStream.forEach(function(record {} item) {
                Ticket|error convertedTicket = item.cloneWithType(Ticket);
                if convertedTicket is Ticket {
                    tickets.push(convertedTicket);
                }
            });

            return tickets;

        } on fail error e {
            log:printError("Error fetching user tickets", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to fetch tickets",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Validate a ticket
    resource function post tickets/validate(TicketValidationRequest request) returns http:Ok|http:BadRequest|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");

            // Fetch the ticket
            map<json> query = {"id": request.ticketId};
            stream<record {}, error?> resultStream = check ticketsCollection->find(query);

            Ticket[] tickets = [];
            error? e = resultStream.forEach(function(record {} item) {
                Ticket|error convertedTicket = item.cloneWithType(Ticket);
                if convertedTicket is Ticket {
                    tickets.push(convertedTicket);
                }
            });

            if tickets.length() == 0 {
                return <http:NotFound>{
                    body: {
                        message: "Ticket not found",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

            Ticket ticket = tickets[0];

            // Check if ticket is paid
            if ticket.status != "PAID" {
                return <http:BadRequest>{
                    body: {
                        message: string `Ticket cannot be validated. Status: ${ticket.status}`,
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

            // Check if ticket has expired
            time:Utc validUntil = check time:utcFromString(ticket.validUntil);
            time:Utc now = time:utcNow();
            time:Seconds timeDiff = time:utcDiffSeconds(validUntil, now);
            decimal timeDiffDecimal = <decimal>timeDiff;

            if timeDiffDecimal < 0.0d {
                // Update status to expired
                mongodb:Update update = {
                    "$set": {
                        "status": "EXPIRED",
                        "updatedAt": time:utcToString(now)
                    }
                };
                _ = check ticketsCollection->updateOne(query, update);
                
                return <http:BadRequest>{
                    body: {
                        message: "Ticket has expired",
                        timestamp: time:utcToString(now)
                    }
                };
            }

            // Check rides remaining for multi-ride tickets 
            int? ridesRemainingValue = ticket.ridesRemaining;
            if ridesRemainingValue is int {
                if ridesRemainingValue <= 0 {
                    return <http:BadRequest>{
                        body: {
                            message: "No rides remaining on this ticket",
                            timestamp: time:utcToString(now)
                        }
                    };
                }
            }

            // Update ticket status
            string currentTime = time:utcToString(now);
            mongodb:Update update = {};
            
            if ridesRemainingValue is int {
                int newRidesRemaining = ridesRemainingValue - 1;
                string newStatus = newRidesRemaining > 0 ? "PAID" : "USED";
                update = {
                    "$set": {
                        "status": newStatus,
                        "ridesRemaining": newRidesRemaining,
                        "validatedAt": currentTime,
                        "validatedBy": request.validatorId,
                        "updatedAt": currentTime
                    }
                };
            } else {
                update = {
                    "$set": {
                        "status": "USED",
                        "validatedAt": currentTime,
                        "validatedBy": request.validatorId,
                        "updatedAt": currentTime
                    }
                };
            }

            _ = check ticketsCollection->updateOne(query, update);

            // Publish validation event to Kafka
            TicketValidatedEvent validationEvent = {
                ticketId: request.ticketId,
                userId: ticket.userId,
                tripId: request.tripId,
                validatedBy: request.validatorId,
                timestamp: currentTime
            };

            error? kafkaResult = kafkaProducer->send({
                topic: "ticket.validated",
                value: validationEvent.toJsonString().toBytes()
            });

            if kafkaResult is error {
                log:printError(string `Failed to publish validation event to Kafka: ${kafkaResult.message()}`, 'error = kafkaResult);
            } else {
                log:printInfo(string `Published validation event to Kafka for ticket: ${request.ticketId}`);
            }

            log:printInfo(string `Ticket validated: ${request.ticketId} by ${request.validatorId}`);
            
            int? remainingRides = ();
            if ridesRemainingValue is int {
                remainingRides = ridesRemainingValue - 1;
            }
            
            return <http:Ok>{
                body: {
                    message: "Ticket validated successfully",
                    ticketId: request.ticketId,
                    ridesRemaining: remainingRides
                }
            };

        } on fail error e {
            log:printError("Error validating ticket", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to validate ticket",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Update ticket status (e.g. after payment)
    resource function put tickets/[string ticketId]/status(string newStatus, string? paymentId) returns http:Ok|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");

            map<json> query = {"id": ticketId};
            string currentTime = time:utcToString(time:utcNow());

            mongodb:Update update = {
                "$set": {
                    "status": newStatus,
                    "updatedAt": currentTime
                }
            };

            // Add paymentId if provided
            if paymentId is string {
                update["$set"]["paymentId"] = paymentId;
            }

            var result = check ticketsCollection->updateOne(query, update);
            
            log:printInfo(string `Ticket ${ticketId} status updated to ${newStatus}`);
            
            return <http:Ok>{
                body: {
                    message: string `Ticket status updated to ${newStatus}`,
                    ticketId: ticketId,
                    status: newStatus
                }
            };

        } on fail error e {
            log:printError("Error updating ticket status", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to update ticket status",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }
}

// Kafka consumer service for payment events - IMPROVED VERSION
service on paymentConsumer {
    remote function onConsumerRecord(kafka:Caller caller, kafka:ConsumerRecord[] records) returns error? {
        log:printInfo(string `Received ${records.length()} payment event(s) from Kafka`);
        
        foreach kafka:ConsumerRecord record in records {
            byte[]|error value = record.value;
            
            if value is byte[] {
                string|error payloadResult = string:fromBytes(value);
                if payloadResult is string {
                    log:printInfo("Raw payment event: " + payloadResult);
                    
                    json|error jsonResult = payloadResult.fromJsonString();
                    if jsonResult is json {
                        PaymentProcessedEvent|error eventResult = jsonResult.cloneWithType(PaymentProcessedEvent);
                        if eventResult is PaymentProcessedEvent {
                            PaymentProcessedEvent event = eventResult;

                            log:printInfo(string `Processing payment event for ticket: ${event.ticketId}, status: ${event.status}, paymentId: ${event.paymentId}`);

                            // Update ticket in MongoDB
                            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
                            mongodb:Collection ticketsCollection = check db->getCollection("tickets");

                            map<json> query = { "id": event.ticketId };
                            string newStatus = event.status == "COMPLETED" ? "PAID" : "PAYMENT_FAILED";
                            string currentTime = time:utcToString(time:utcNow());

                            mongodb:Update update = {
                                "$set": {
                                    "status": newStatus,
                                    "paymentId": event.paymentId,
                                    "updatedAt": currentTime
                                }
                            };

                            var updateResult = check ticketsCollection->updateOne(query, update);
                            
                            if updateResult is mongodb:UpdateResult {
                                if updateResult.matchedCount > 0 {
                                    log:printInfo(string `Ticket ${event.ticketId} status updated to ${newStatus}`);
                                } else {
                                    log:printWarn(string `No ticket found with ID: ${event.ticketId} to update`);
                                }
                            }
                            
                            // Commit the offset after successful processing
                            check caller->commit([record]);
                            
                        } else {
                            log:printError("Failed to cast payload to PaymentProcessedEvent", 'error = eventResult);
                        }
                    } else {
                        log:printError("Failed to parse payload to JSON", 'error = jsonResult);
                    }
                } else {
                    log:printError("Failed to convert bytes to string", 'error = payloadResult);
                }
            } else {
                log:printWarn("Could not extract byte[] value from Kafka record");
            }
        }
        return;
    }
}

// Initialize function to log service startup
public function init() returns error? {
    log:printInfo("Ticketing Service starting...");
    log:printInfo(string `Kafka bootstrap servers: ${kafkaBootstrapServers}`);
    log:printInfo(string `MongoDB host: ${mongoHost}:${mongoPort}`);
    log:printInfo("Ticketing Service initialized successfully");
}