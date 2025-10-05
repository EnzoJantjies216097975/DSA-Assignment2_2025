import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerina/random;
import ballerinax/kafka;
import ballerinax/mongodb;
import ballerina/runtime;

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
    clientId: "payment-service",
    acks: "all",
    retryCount: 3
});

// Kafka consumer for ticket events
kafka:Consumer kafkaConsumer = check new ({
    bootstrapServers: kafkaBootstrapServers,
    groupId: "payment-service-group",
    topics: ["ticket.requests", "ticket.cancellations", "payment.events"],
    autoOffsetReset: "earliest"
});

// Define payment-related record types
type Payment record {
    string id?;
    string paymentId;
    string userId;
    string ticketId;
    decimal amount;
    string currency;
    string paymentMethod;
    string status;
    string transactionReference?;
    string processedAt?;
    PaymentDetails paymentDetails?;
    RefundDetails refundDetails?;
    string createdAt?;
    string updatedAt?;
};

type PaymentDetails record {
    string cardLastFourDigits?;
    string bankName?;
    string mobileProvider?;
};

type RefundDetails record {
    string refundedAt;
    decimal refundAmount;
    string refundReason;
};

type PaymentRequest record {
    string userId;
    string ticketId;
    decimal amount;
    string paymentMethod;
    PaymentDetails paymentDetails?;
};

type RefundRequest record {
    string paymentId;
    string reason;
    decimal amount?;
};

type User record {
    string id;
    string username;
    decimal accountBalance;
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
service /payment on new http:Listener(8084) {
    
    // Initialize Kafka consumer listener on startup
    function init() returns error? {
        _ = start consumeKafkaEvents();
        log:printInfo("Payment service started and listening to Kafka events");
    }
    
    // Process a payment
    resource function post process(@http:Payload PaymentRequest request) 
            returns Payment|http:BadRequest|http:InternalServerError {
        // Validate payment amount
        if request.amount <= 0 {
            return <http:BadRequest>{
                body: {"error": "Invalid payment amount"}
            };
        }
        
        // Generate payment ID and transaction reference
        string paymentId = "PAY-" + uuid:createType1AsString().substring(0, 12).toUpperAscii();
        string transactionRef = "TXN-" + uuid:createType1AsString().substring(0, 16).toUpperAscii();
        string currentTime = time:utcToString(time:utcNow());
        
        // Create payment record
        Payment payment = {
            paymentId: paymentId,
            userId: request.userId,
            ticketId: request.ticketId,
            amount: request.amount,
            currency: "NAD",
            paymentMethod: request.paymentMethod,
            status: "PENDING",
            transactionReference: transactionRef,
            paymentDetails: request.paymentDetails,
            createdAt: currentTime,
            updatedAt: currentTime
        };
        
        // Insert payment into database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");
        
        check paymentsCollection->insertOne(payment);
        
        // Process payment based on method
        boolean paymentSuccess = false;
        string failureReason = "";
        
        if request.paymentMethod == "ACCOUNT_BALANCE" {
            // Check and deduct from user balance
            var result = check processAccountBalancePayment(request.userId, request.amount);
            paymentSuccess = result;
            if !paymentSuccess {
                failureReason = "Insufficient balance";
            }
        } else {
            // Simulate external payment gateway processing
            paymentSuccess = check simulatePaymentGateway(request.paymentMethod, request.amount);
            if !paymentSuccess {
                failureReason = "Payment gateway error";
            }
        }
        
        // Update payment status
        string newStatus = paymentSuccess ? "COMPLETED" : "FAILED";
        map<json> filter = {"paymentId": paymentId};
        map<json> update = {
            "$set": {
                "status": newStatus,
                "processedAt": time:utcToString(time:utcNow()),
                "updatedAt": time:utcToString(time:utcNow())
            }
        };
        
        if !paymentSuccess && failureReason != "" {
            update["$set"]["failureReason"] = failureReason;
        }
        
        mongodb:UpdateResult updateResult = check paymentsCollection->updateOne(filter, update);
        
        // Publish payment event
        string eventType = paymentSuccess ? "PAYMENT_COMPLETED" : "PAYMENT_FAILED";
        kafka:ProducerRecord paymentEvent = {
            topic: "payments.processed",
            key: paymentId.toBytes(),
            value: {
                "eventType": eventType,
                "paymentId": paymentId,
                "userId": request.userId,
                "ticketId": request.ticketId,
                "amount": request.amount,
                "status": newStatus,
                "failureReason": failureReason,
                "timestamp": time:utcToString(time:utcNow())
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(paymentEvent);
        
        log:printInfo("Payment processed: " + paymentId + " - Status: " + newStatus);
        
        payment.status = newStatus;
        payment.processedAt = time:utcToString(time:utcNow());
        
        return payment;
    }
    
    // Get payment by ID
    resource function get payments/[string paymentId]() returns Payment|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");
        
        map<json> query = {"paymentId": paymentId};
        stream<Payment, error?> payments = check paymentsCollection->find(query);
        
        Payment|error? payment = payments.next();
        if payment is Payment {
            return payment;
        }
        
        return <http:NotFound>{
            body: {"error": "Payment not found"}
        };
    }
    
    // Get user's payment history
    resource function get users/[string userId]/payments(string? status = ()) 
            returns Payment[]|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");
        
        map<json> query = {"userId": userId};
        if status is string {
            query["status"] = status;
        }
        
        stream<Payment, error?> paymentsStream = check paymentsCollection->find(query);
        
        Payment[] payments = [];
        check from Payment payment in paymentsStream
            do {
                payments.push(payment);
            };
        
        return payments;
    }
    
    // Process a refund
    resource function post refunds(@http:Payload RefundRequest request) 
            returns map<json>|http:BadRequest|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");
        
        // Find original payment
        map<json> query = {"paymentId": request.paymentId};
        stream<Payment, error?> payments = check paymentsCollection->find(query);
        
        Payment|error? payment = payments.next();
        if payment is () || payment is error {
            return <http:NotFound>{
                body: {"error": "Payment not found"}
            };
        }
        
        // Validate payment status
        if payment.status != "COMPLETED" {
            return <http:BadRequest>{
                body: {
                    "error": "Cannot refund payment",
                    "status": payment.status
                }
            };
        }
        
        // Check if already refunded
        if payment.status == "REFUNDED" {
            return <http:BadRequest>{
                body: {"error": "Payment already refunded"}
            };
        }
        
        // Calculate refund amount
        decimal refundAmount = request.amount ?: payment.amount;
        if refundAmount > payment.amount {
            return <http:BadRequest>{
                body: {
                    "error": "Refund amount exceeds original payment",
                    "originalAmount": payment.amount,
                    "requestedRefund": refundAmount
                }
            };
        }
        
        // Process refund
        string currentTime = time:utcToString(time:utcNow());
        RefundDetails refundDetails = {
            refundedAt: currentTime,
            refundAmount: refundAmount,
            refundReason: request.reason
        };
        
        // Update payment record
        map<json> update = {
            "$set": {
                "status": "REFUNDED",
                "refundDetails": refundDetails,
                "updatedAt": currentTime
            }
        };
        
        mongodb:UpdateResult updateResult = check paymentsCollection->updateOne(query, update);
        
        // If account balance payment, credit back to user
        if payment.paymentMethod == "ACCOUNT_BALANCE" {
            check creditUserBalance(payment.userId, refundAmount);
        }
        
        // Publish refund event
        kafka:ProducerRecord refundEvent = {
            topic: "payments.processed",
            key: request.paymentId.toBytes(),
            value: {
                "eventType": "PAYMENT_REFUNDED",
                "paymentId": request.paymentId,
                "userId": payment.userId,
                "ticketId": payment.ticketId,
                "refundAmount": refundAmount,
                "refundReason": request.reason,
                "timestamp": currentTime
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(refundEvent);
        
        log:printInfo("Refund processed: " + request.paymentId + " - Amount: " + refundAmount.toString());
        
        return {
            "status": "success",
            "message": "Refund processed successfully",
            "paymentId": request.paymentId,
            "refundAmount": refundAmount,
            "refundReference": "REF-" + uuid:createType1AsString().substring(0, 12).toUpperAscii()
        };
    }
    
    // Get payment statistics
    resource function get statistics(string? startDate = (), string? endDate = (), string? groupBy = "day") 
            returns map<json>|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");
        
        map<json> query = {"status": "COMPLETED"};
        if startDate is string && endDate is string {
            query["processedAt"] = {
                "$gte": startDate,
                "$lte": endDate
            };
        }
        
        stream<Payment, error?> paymentsStream = check paymentsCollection->find(query);
        
        // Calculate statistics
        decimal totalRevenue = 0.0;
        int totalTransactions = 0;
        map<decimal> revenueByMethod = {};
        map<int> countByMethod = {};
        decimal totalRefunds = 0.0;
        int refundCount = 0;
        
        check from Payment payment in paymentsStream
            do {
                if payment.status == "COMPLETED" {
                    totalRevenue = totalRevenue + payment.amount;
                    totalTransactions += 1;
                    
                    // Group by payment method
                    decimal currentMethodRevenue = revenueByMethod[payment.paymentMethod] ?: 0.0;
                    revenueByMethod[payment.paymentMethod] = currentMethodRevenue + payment.amount;
                    
                    int currentMethodCount = countByMethod[payment.paymentMethod] ?: 0;
                    countByMethod[payment.paymentMethod] = currentMethodCount + 1;
                    
                } else if payment.status == "REFUNDED" {
                    RefundDetails? refundDetails = payment.refundDetails;
                    if refundDetails is RefundDetails {
                        totalRefunds = totalRefunds + refundDetails.refundAmount;
                        refundCount += 1;
                    }
                }
            };
        
        return {
            "totalRevenue": totalRevenue,
            "totalTransactions": totalTransactions,
            "averageTransactionValue": totalTransactions > 0 ? totalRevenue / <decimal>totalTransactions : 0.0,
            "revenueByMethod": revenueByMethod,
            "transactionsByMethod": countByMethod,
            "refunds": {
                "totalAmount": totalRefunds,
                "count": refundCount
            },
            "netRevenue": totalRevenue - totalRefunds,
            "period": {
                "startDate": startDate ?: "all-time",
                "endDate": endDate ?: "all-time"
            }
        };
    }
    
    // Verify payment status (for external queries)
    resource function get verify/[string transactionReference]() 
            returns map<json>|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");
        
        map<json> query = {"transactionReference": transactionReference};
        stream<Payment, error?> payments = check paymentsCollection->find(query);
        
        Payment|error? payment = payments.next();
        if payment is Payment {
            return {
                "paymentId": payment.paymentId,
                "status": payment.status,
                "amount": payment.amount,
                "currency": payment.currency,
                "processedAt": payment.processedAt,
                "verified": true
            };
        }
        
        return <http:NotFound>{
            body: {"error": "Transaction not found", "verified": false}
        };
    }
}

// Helper function to process account balance payment
function processAccountBalancePayment(string userId, decimal amount) returns boolean|error {
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection usersCollection = check db->getCollection("users");
    
    // Check user balance
    map<json> query = {"id": userId};
    stream<User, error?> users = check usersCollection->find(query);
    
    User|error? user = users.next();
    if user is User {
        if user.accountBalance >= amount {
            // Deduct balance
            map<json> update = {
                "$inc": {"accountBalance": -amount},
                "$set": {"updatedAt": time:utcToString(time:utcNow())}
            };
            
            mongodb:UpdateResult result = check usersCollection->updateOne(query, update);
            
            // Publish balance update event
            kafka:ProducerRecord balanceEvent = {
                topic: "payment.events",
                key: userId.toBytes(),
                value: {
                    "eventType": "BALANCE_DEDUCTED",
                    "userId": userId,
                    "amount": amount,
                    "newBalance": user.accountBalance - amount,
                    "timestamp": time:utcToString(time:utcNow())
                }.toJsonString().toBytes()
            };
            
            check kafkaProducer->send(balanceEvent);
            
            return true;
        }
    }
    
    return false;
}

// Helper function to credit user balance (for refunds)
function creditUserBalance(string userId, decimal amount) returns error? {
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection usersCollection = check db->getCollection("users");
    
    map<json> query = {"id": userId};
    map<json> update = {
        "$inc": {"accountBalance": amount},
        "$set": {"updatedAt": time:utcToString(time:utcNow())}
    };
    
    mongodb:UpdateResult result = check usersCollection->updateOne(query, update);
    
    // Publish balance update event
    kafka:ProducerRecord balanceEvent = {
        topic: "payment.events",
        key: userId.toBytes(),
        value: {
            "eventType": "BALANCE_CREDITED",
            "userId": userId,
            "amount": amount,
            "reason": "refund",
            "timestamp": time:utcToString(time:utcNow())
        }.toJsonString().toBytes()
    };
    
    check kafkaProducer->send(balanceEvent);
}

// Helper function to simulate payment gateway
function simulatePaymentGateway(string paymentMethod, decimal amount) returns boolean|error {
    // Simulate payment processing delay
    runtime:sleep(0.5); // 500ms delay
    
    // Simulate success rate (95% success for demo)
    int randomNum = check random:createIntInRange(1, 100);
    
    if paymentMethod == "CARD" {
        // Card payments have 95% success rate
        return randomNum <= 95;
    } else if paymentMethod == "MOBILE_MONEY" {
        // Mobile money has 92% success rate
        return randomNum <= 92;
    }
    
    // Default success rate
    return randomNum <= 90;
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
            
            if kafkaRecord.topic == "ticket.requests" {
                check handleTicketRequest(eventType, message);
            } else if kafkaRecord.topic == "ticket.cancellations" {
                check handleTicketCancellation(eventType, message);
            }
        }
        
        check kafkaConsumer->commit();
    }
}

// Handle ticket request events
function handleTicketRequest(string eventType, json message) returns error? {
    if eventType == "TICKET_REQUESTED" {
        // Automatically process payment for ticket
        PaymentRequest paymentRequest = {
            userId: check message.userId,
            ticketId: check message.ticketId,
            amount: check message.price.ensureType(decimal),
            paymentMethod: check message.paymentMethod
        };
        
        // Process the payment
        http:Client paymentClient = check new ("http://localhost:8084");
        http:Response response = check paymentClient->post("/payment/process", paymentRequest);
        
        if response.statusCode == 200 {
            log:printInfo("Auto-processed payment for ticket: " + paymentRequest.ticketId);
        }
    }
}

// Handle ticket cancellation events
function handleTicketCancellation(string eventType, json message) returns error? {
    if eventType == "TICKET_CANCELLED" {
        string? paymentId = check message.paymentId;
        
        if paymentId is string {
            // Process refund for cancelled ticket
            RefundRequest refundRequest = {
                paymentId: paymentId,
                reason: "Ticket cancellation"
            };
            
            http:Client paymentClient = check new ("http://localhost:8084");
            http:Response response = check paymentClient->post("/payment/refunds", refundRequest);
            
            if response.statusCode == 200 {
                log:printInfo("Auto-processed refund for cancelled ticket payment: " + paymentId);
            }
        }
    }
}