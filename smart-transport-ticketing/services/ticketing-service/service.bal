import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerina/crypto;
import ballerinax/kafka;
import ballerinax/mongodb;

// Configuration for MongoDB connection
configurable string mongodbUrl = "mongodb://localhost:27017";
configurable string databaseName = "transport_db";

// Configuration for Kafka
configurable string kafkaBootstrapServers = "localhost:9092";

// MongoDB client for database operations
mongodb:Client mongoClient = check new (mongodbUrl);

// Kafka producer for publishing events
kafka:Producer kafkaProducer = check new ({
    bootstrapServers: kafkaBootstrapServers,
    clientId: "ticketing-service",
    acks: "all",
    retryCount: 3
});

// Kafka consumer for payment events
kafka:Consumer kafkaConsumer = check new ({
    bootstrapServers: kafkaBootstrapServers,
    groupId: "ticketing-service-group",
    topics: ["payments.processed", "schedule.updates"],
    autoOffsetReset: "earliest"
});

// Define ticket-related record types
type Ticket record {
    string id?;
    string ticketId;
    string userId;
    string ticketType;
    string status;
    decimal price;
    string purchaseDate;
    string validFrom;
    string validUntil;
    TripDetails tripDetails?;
    ValidationRecord[] validationHistory?;
    string paymentId?;
    string qrCode;
    string createdAt?;
    string updatedAt?;
};

type TripDetails record {
    string tripId;
    string routeId;
    string boardingStop;
    string destinationStop;
};

type ValidationRecord record {
    string validatedAt;
    string validatorId;
    string location;
    string vehicleId;
};

type TicketRequest record {
    string userId;
    string ticketType;
    TripDetails tripDetails?;
    string paymentMethod;
};

type TicketPricing record {
    string ticketType;
    decimal basePrice;
    decimal discount?;
    decimal finalPrice;
};

type ValidationRequest record {
    string ticketId;
    string validatorId;
    string vehicleId;
    string location;
};

// Ticket types and their base prices
map<decimal> ticketPrices = {
    "SINGLE": 15.00,
    "RETURN": 25.00,
    "DAY_PASS": 40.00,
    "WEEK_PASS": 200.00,
    "MONTH_PASS": 600.00
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
service /ticketing on new http:Listener(8083) {
    
    // Initialize Kafka consumer listener on startup
    function init() returns error? {
        _ = start consumeKafkaEvents();
        log:printInfo("Ticketing service started and listening to Kafka events");
    }
    
    // Request a new ticket
    resource function post tickets(@http:Payload TicketRequest request) 
            returns Ticket|http:BadRequest|http:InternalServerError {
        // Validate ticket type
        if !ticketPrices.hasKey(request.ticketType) {
            return <http:BadRequest>{
                body: {"error": "Invalid ticket type"}
            };
        }
        
        // Generate ticket ID and calculate validity period
        string ticketId = "TKT-" + uuid:createType1AsString().substring(0, 12).toUpperAscii();
        string currentTime = time:utcToString(time:utcNow());
        
        // Calculate valid from and valid until based on ticket type
        time:Utc validFromTime = time:utcNow();
        time:Utc validUntilTime;
        
        if request.ticketType == "SINGLE" || request.ticketType == "RETURN" {
            // Valid for 24 hours from purchase
            validUntilTime = time:utcAddSeconds(validFromTime, 86400);
        } else if request.ticketType == "DAY_PASS" {
            // Valid until end of day
            validUntilTime = time:utcAddSeconds(validFromTime, 86400);
        } else if request.ticketType == "WEEK_PASS" {
            // Valid for 7 days
            validUntilTime = time:utcAddSeconds(validFromTime, 604800);
        } else if request.ticketType == "MONTH_PASS" {
            // Valid for 30 days
            validUntilTime = time:utcAddSeconds(validFromTime, 2592000);
        } else {
            validUntilTime = time:utcAddSeconds(validFromTime, 86400);
        }
        
        // Calculate price (could include dynamic pricing based on route/time)
        decimal price = ticketPrices.get(request.ticketType);
        
        // Generate QR code data
        string qrData = ticketId + "|" + request.userId + "|" + request.ticketType;
        byte[] qrHash = crypto:hashSha256(qrData.toBytes());
        string qrCode = qrHash.toBase64();
        
        // Create ticket
        Ticket ticket = {
            ticketId: ticketId,
            userId: request.userId,
            ticketType: request.ticketType,
            status: "CREATED",
            price: price,
            purchaseDate: currentTime,
            validFrom: time:utcToString(validFromTime),
            validUntil: time:utcToString(validUntilTime),
            tripDetails: request.tripDetails,
            qrCode: qrCode,
            createdAt: currentTime,
            updatedAt: currentTime
        };
        
        // Insert ticket into database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        
        check ticketsCollection->insertOne(ticket);
        
        // Publish ticket request event to Kafka for payment processing
        kafka:ProducerRecord ticketRequestEvent = {
            topic: "ticket.requests",
            key: ticketId.toBytes(),
            value: {
                "eventType": "TICKET_REQUESTED",
                "ticketId": ticketId,
                "userId": request.userId,
                "ticketType": request.ticketType,
                "price": price,
                "paymentMethod": request.paymentMethod,
                "tripDetails": request.tripDetails,
                "timestamp": currentTime
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(ticketRequestEvent);
        
        log:printInfo("Ticket requested: " + ticketId);
        return ticket;
    }
    
    // Get ticket by ID
    resource function get tickets/[string ticketId]() returns Ticket|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        
        map<json> query = {"ticketId": ticketId};
        stream<Ticket, error?> tickets = check ticketsCollection->find(query);
        
        Ticket|error? ticket = tickets.next();
        if ticket is Ticket {
            return ticket;
        }
        
        return <http:NotFound>{
            body: {"error": "Ticket not found"}
        };
    }
    
    // Get user's tickets
    resource function get users/[string userId]/tickets(string? status = ()) 
            returns Ticket[]|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        
        map<json> query = {"userId": userId};
        if status is string {
            query["status"] = status;
        }
        
        stream<Ticket, error?> ticketsStream = check ticketsCollection->find(query);
        
        Ticket[] tickets = [];
        check from Ticket ticket in ticketsStream
            do {
                tickets.push(ticket);
            };
        
        return tickets;
    }
    
    // Validate a ticket
    resource function post tickets/validate(@http:Payload ValidationRequest request) 
            returns map<json>|http:BadRequest|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        
        // Find ticket
        map<json> query = {"ticketId": request.ticketId};
        stream<Ticket, error?> tickets = check ticketsCollection->find(query);
        
        Ticket|error? ticket = tickets.next();
        if ticket is () || ticket is error {
            return <http:NotFound>{
                body: {"error": "Ticket not found"}
            };
        }
        
        // Check ticket status
        if ticket.status != "PAID" && ticket.status != "VALIDATED" {
            return <http:BadRequest>{
                body: {
                    "error": "Ticket cannot be validated",
                    "status": ticket.status,
                    "reason": ticket.status == "CREATED" ? "Payment pending" : "Ticket expired or cancelled"
                }
            };
        }
        
        // Check validity period
        time:Utc currentTime = time:utcNow();
        time:Utc|error validUntil = time:utcFromString(ticket.validUntil);
        
        if validUntil is time:Utc {
            if time:utcDiffSeconds(validUntil, currentTime) < 0 {
                // Ticket has expired, update status
                map<json> expireUpdate = {
                    "$set": {
                        "status": "EXPIRED",
                        "updatedAt": time:utcToString(currentTime)
                    }
                };
                
                check ticketsCollection->updateOne(query, expireUpdate);
                
                return <http:BadRequest>{
                    body: {
                        "error": "Ticket has expired",
                        "expiredAt": ticket.validUntil
                    }
                };
            }
        }
        
        // For single tickets, check if already validated
        if ticket.ticketType == "SINGLE" && ticket.status == "VALIDATED" {
            return <http:BadRequest>{
                body: {
                    "error": "Single ticket already used",
                    "validatedAt": ticket.validationHistory is ValidationRecord[] ? 
                        ticket.validationHistory[0].validatedAt : "unknown"
                }
            };
        }
        
        // Create validation record
        ValidationRecord validation = {
            validatedAt: time:utcToString(currentTime),
            validatorId: request.validatorId,
            location: request.location,
            vehicleId: request.vehicleId
        };
        
        // Update ticket with validation
        ValidationRecord[] validationHistory = ticket.validationHistory ?: [];
        validationHistory.push(validation);
        
        string newStatus = ticket.ticketType == "SINGLE" ? "VALIDATED" : "PAID";
        
        map<json> update = {
            "$set": {
                "status": newStatus,
                "validationHistory": validationHistory,
                "updatedAt": time:utcToString(currentTime)
            }
        };
        
        mongodb:UpdateResult updateResult = check ticketsCollection->updateOne(query, update);
        
        // Publish validation event
        kafka:ProducerRecord validationEvent = {
            topic: "ticket.validations",
            key: request.ticketId.toBytes(),
            value: {
                "eventType": "TICKET_VALIDATED",
                "ticketId": request.ticketId,
                "userId": ticket.userId,
                "ticketType": ticket.ticketType,
                "validatorId": request.validatorId,
                "vehicleId": request.vehicleId,
                "location": request.location,
                "timestamp": time:utcToString(currentTime)
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(validationEvent);
        
        log:printInfo("Ticket validated: " + request.ticketId);
        
        return {
            "status": "success",
            "message": "Ticket validated successfully",
            "ticketId": request.ticketId,
            "validationType": ticket.ticketType,
            "remainingValidity": ticket.ticketType != "SINGLE" ? ticket.validUntil : "Used"
        };
    }
    
    // Get ticket pricing
    resource function get pricing(string? ticketType = ()) returns TicketPricing[]|TicketPricing|http:BadRequest {
        if ticketType is string {
            if !ticketPrices.hasKey(ticketType) {
                return <http:BadRequest>{
                    body: {"error": "Invalid ticket type"}
                };
            }
            
            decimal basePrice = ticketPrices.get(ticketType);
            return {
                ticketType: ticketType,
                basePrice: basePrice,
                discount: 0.0,
                finalPrice: basePrice
            };
        }
        
        // Return all pricing
        TicketPricing[] pricing = [];
        foreach string tType in ticketPrices.keys() {
            decimal basePrice = ticketPrices.get(tType);
            pricing.push({
                ticketType: tType,
                basePrice: basePrice,
                discount: 0.0,
                finalPrice: basePrice
            });
        }
        
        return pricing;
    }
    
    // Cancel a ticket
    resource function post tickets/[string ticketId]/cancel() 
            returns map<json>|http:NotFound|http:BadRequest|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        
        // Find ticket
        map<json> query = {"ticketId": ticketId};
        stream<Ticket, error?> tickets = check ticketsCollection->find(query);
        
        Ticket|error? ticket = tickets.next();
        if ticket is () || ticket is error {
            return <http:NotFound>{
                body: {"error": "Ticket not found"}
            };
        }
        
        // Check if ticket can be cancelled
        if ticket.status == "VALIDATED" || ticket.status == "EXPIRED" || ticket.status == "CANCELLED" {
            return <http:BadRequest>{
                body: {
                    "error": "Ticket cannot be cancelled",
                    "status": ticket.status
                }
            };
        }
        
        // Update ticket status
        string currentTime = time:utcToString(time:utcNow());
        map<json> update = {
            "$set": {
                "status": "CANCELLED",
                "updatedAt": currentTime
            }
        };
        
        mongodb:UpdateResult updateResult = check ticketsCollection->updateOne(query, update);
        
        // Publish cancellation event
        kafka:ProducerRecord cancellationEvent = {
            topic: "ticket.cancellations",
            key: ticketId.toBytes(),
            value: {
                "eventType": "TICKET_CANCELLED",
                "ticketId": ticketId,
                "userId": ticket.userId,
                "ticketType": ticket.ticketType,
                "price": ticket.price,
                "paymentId": ticket.paymentId,
                "timestamp": currentTime
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(cancellationEvent);
        
        log:printInfo("Ticket cancelled: " + ticketId);
        
        return {
            "status": "success",
            "message": "Ticket cancelled successfully",
            "ticketId": ticketId,
            "refundAmount": ticket.status == "PAID" ? ticket.price : 0.0
        };
    }
    
    // Get ticket statistics for reporting
    resource function get statistics(string? startDate = (), string? endDate = ()) 
            returns map<json>|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        
        map<json> query = {};
        if startDate is string && endDate is string {
            query["purchaseDate"] = {
                "$gte": startDate,
                "$lte": endDate
            };
        }
        
        stream<Ticket, error?> ticketsStream = check ticketsCollection->find(query);
        
        // Calculate statistics
        int totalTickets = 0;
        decimal totalRevenue = 0.0;
        map<int> ticketTypeCount = {};
        map<int> statusCount = {};
        
        check from Ticket ticket in ticketsStream
            do {
                totalTickets += 1;
                if ticket.status == "PAID" || ticket.status == "VALIDATED" {
                    totalRevenue = totalRevenue + ticket.price;
                }
                
                // Count by type
                int currentTypeCount = ticketTypeCount[ticket.ticketType] ?: 0;
                ticketTypeCount[ticket.ticketType] = currentTypeCount + 1;
                
                // Count by status
                int currentStatusCount = statusCount[ticket.status] ?: 0;
                statusCount[ticket.status] = currentStatusCount + 1;
            };
        
        return {
            "totalTickets": totalTickets,
            "totalRevenue": totalRevenue,
            "ticketsByType": ticketTypeCount,
            "ticketsByStatus": statusCount,
            "period": {
                "startDate": startDate ?: "all-time",
                "endDate": endDate ?: "all-time"
            }
        };
    }
}

// Kafka event consumer function
function consumeKafkaEvents() returns error? {
    while true {
        kafka:ConsumerRecord[] records = check kafkaConsumer->poll(1000);
        
        foreach kafka:ConsumerRecord kafkaRecord in records {
            byte[] value = kafkaRecord.value;
            string messageStr = check string:fromBytes(value);
            json message = check messageStr.fromJsonString();
            
            string eventType = check message.eventType;
            
            if kafkaRecord.topic == "payments.processed" {
                check handlePaymentEvent(eventType, message);
            } else if kafkaRecord.topic == "schedule.updates" {
                check handleScheduleUpdate(eventType, message);
            }
        }
        
        check kafkaConsumer->commit();
    }
}

// Handle payment events
function handlePaymentEvent(string eventType, json message) returns error? {
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection ticketsCollection = check db->getCollection("tickets");
    
    if eventType == "PAYMENT_COMPLETED" {
        string ticketId = check message.ticketId;
        string paymentId = check message.paymentId;
        
        // Update ticket status to PAID
        map<json> filter = {"ticketId": ticketId};
        map<json> update = {
            "$set": {
                "status": "PAID",
                "paymentId": paymentId,
                "updatedAt": time:utcToString(time:utcNow())
            }
        };
        
        mongodb:UpdateResult result = check ticketsCollection->updateOne(filter, update);
        log:printInfo("Ticket payment confirmed: " + ticketId);
        
    } else if eventType == "PAYMENT_FAILED" {
        string ticketId = check message.ticketId;
        
        // Update ticket status to CANCELLED
        map<json> filter = {"ticketId": ticketId};
        map<json> update = {
            "$set": {
                "status": "CANCELLED",
                "updatedAt": time:utcToString(time:utcNow())
            }
        };
        
        mongodb:UpdateResult result = check ticketsCollection->updateOne(filter, update);
        log:printInfo("Ticket cancelled due to payment failure: " + ticketId);
    }
}

// Handle schedule update events
function handleScheduleUpdate(string eventType, json message) returns error? {
    // Handle trip cancellations or delays that might affect tickets
    if eventType == "TRIP_CANCELLED" || eventType == "SERVICE_DISRUPTION" {
        log:printInfo("Schedule update received: " + eventType);
        
        // Could trigger notifications to affected passengers
        // This would integrate with the notification service
        kafka:ProducerRecord notificationTrigger = {
            topic: "notification.triggers",
            key: "schedule-update".toBytes(),
            value: message.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(notificationTrigger);
    }
}
