import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;
import ballerina/lang.runtime;

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
    clientId: "payment-service-producer",
    acks: "all",
    retryCount: 3
});

// Kafka consumer for ticket requests - SIMPLE CONFIG
listener kafka:Listener ticketRequestListener = new (kafkaBootstrapServers, {
    groupId: "payment-ticket-group",
    topics: ["ticket.requests"]
});

// Types
public type Payment record {|
    string id;
    string ticketId;
    string userId;
    decimal amount;
    string paymentMethod;
    string status;
    string transactionId?;
    string createdAt;
    string completedAt?;
|};

public type ProcessPaymentRequest record {|
    string ticketId;
    string userId;
    decimal amount;
    string paymentMethod;
|};

public type TicketRequestEvent record {|
    string ticketId;
    string userId;
    string tripId?;
    string ticketType;
    decimal price;
    string timestamp;
|};

public type PaymentProcessedEvent record {|
    string ticketId;
    string userId;
    string paymentId;
    string status;
    decimal amount;
    string timestamp;
|};

// Process payment function
function processPayment(string ticketId, string userId, decimal amount, string paymentMethod) returns string|error {
    log:printInfo(string `PROCESSING PAYMENT: ticket=${ticketId}, user=${userId}, amount=${amount}`);
    
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    mongodb:Collection paymentsCollection = check db->getCollection("payments");

    string paymentId = uuid:createType1AsString();
    string currentTime = time:utcToString(time:utcNow());
    
    // Simulate payment processing
    runtime:sleep(2);
    boolean paymentSuccess = true; // Always succeed for testing
    
    string paymentStatus = paymentSuccess ? "COMPLETED" : "FAILED";
    string transactionId = paymentSuccess ? uuid:createType1AsString() : "";
    
    Payment newPayment = {
        id: paymentId,
        ticketId: ticketId,
        userId: userId,
        amount: amount,
        paymentMethod: paymentMethod,
        status: paymentStatus,
        transactionId: transactionId,
        createdAt: currentTime,
        completedAt: paymentSuccess ? currentTime : ()
    };

    check paymentsCollection->insertOne(newPayment);
    
    // Publish payment processed event
    PaymentProcessedEvent paymentEvent = {
        ticketId: ticketId,
        userId: userId,
        paymentId: paymentId,
        status: paymentStatus,
        amount: amount,
        timestamp: currentTime
    };

    check kafkaProducer->send({
        topic: "payments.processed",
        value: paymentEvent.toJsonString().toBytes()
    });

    log:printInfo(string `PAYMENT SUCCESS: ${paymentId} for ticket ${ticketId}`);
    return paymentStatus;
}

// HTTP Service
service /payment on new http:Listener(9093) {
    
    resource function get health() returns string {
        log:printInfo("Health check - HTTP service working");
        return "Payment Service is running";
    }

    resource function post payments/process(ProcessPaymentRequest request) returns http:Created|http:BadRequest|http:InternalServerError {
        do {
            log:printInfo(string `Manual payment for ticket: ${request.ticketId}`);
            string paymentStatus = check processPayment(request.ticketId, request.userId, request.amount, request.paymentMethod);
            
            return <http:Created>{
                body: {
                    message: "Payment processed successfully",
                    paymentId: uuid:createType1AsString(),
                    status: paymentStatus
                }
            };

        } on fail error e {
            log:printError("Payment processing failed", 'error = e);
            return <http:InternalServerError>{
                body: { message: "Failed to process payment" }
            };
        }
    }
}

// SIMPLE KAFKA CONSUMER SERVICE
@kafka:ServiceConfig {
    topic: "ticket.requests",
    groupId: "payment-ticket-group",
    autoCommit: true
}
service kafka:Service on ticketRequestListener {
    
    remote function onConsumerRecord(kafka:Caller caller, kafka:ConsumerRecord[] records) returns error? {
        log:printInfo(string `KAFKA: Received ${records.length()} records`);
        
        foreach var record in records {
            log:printInfo("KAFKA: Processing record...");
            
            // Simple processing - just log and process
            string message = check string:fromBytes(check record.value);
            log:printInfo("KAFKA Message: " + message);
            
            // Parse and process
            json jsonData = check message.fromJsonString();
            TicketRequestEvent event = check jsonData.cloneWithType(TicketRequestEvent);
            
            log:printInfo(string `KAFKA: Processing ticket ${event.ticketId}, amount ${event.price}`);
            
            // Process payment
            error? result = processPayment(event.ticketId, event.userId, event.price, "KAFKA_AUTO");
            if result is error {
                log:printError(string `KAFKA: Payment failed for ${event.ticketId}`, 'error = result);
            } else {
                log:printInfo(string `KAFKA: Payment successful for ${event.ticketId}`);
            }
        }
        return;
    }
}

public function main() returns error? {
    log:printInfo("=== PAYMENT SERVICE STARTED ===");
    log:printInfo("Kafka: " + kafkaBootstrapServers);
    log:printInfo("MongoDB: " + mongoHost + ":" + mongoPort.toString());
    log:printInfo("HTTP: 9093, Kafka Consumer: ACTIVE");
    log:printInfo("=== READY FOR TICKET REQUESTS ===");
}