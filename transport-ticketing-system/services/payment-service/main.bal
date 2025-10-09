import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;
import ballerina/lang.runtime;

// Configuration
configurable string mongoHost = ?;
configurable int mongoPort = ?;
configurable string mongoUsername = ?;
configurable string mongoPassword = ?;
configurable string mongoDatabase = ?;
configurable string kafkaBootstrapServers = ?;

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

// Kafka consumer for ticket requests
listener kafka:Listener ticketRequestListener = new (kafkaBootstrapServers, {
    groupId: "payment-ticket-group",
    topics: ["ticket.requests"],
    pollingInterval: 1.0,
    autoCommit: false
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

// Simulated payment processing
function simulatePaymentProcessing() returns boolean {
    // Simulate 95% success rate
    int random = <int>(time:utcNow()[0] % 100);
    return random < 95;
}

// Process payment function
function processPayment(string ticketId, string userId, decimal amount, string paymentMethod) returns string|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    mongodb:Collection paymentsCollection = check db->getCollection("payments");

    string paymentId = uuid:createType1AsString();
    string currentTime = time:utcToString(time:utcNow());
    
    // Simulate payment processing delay
    runtime:sleep(2);
    boolean paymentSuccess = simulatePaymentProcessing();
    
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

    log:printInfo(string `Payment ${paymentStatus} for ticket: ${ticketId}, paymentId: ${paymentId}`);
    return paymentStatus;
}

// HTTP Service
service /payment on new http:Listener(9093) {
    
    resource function get health() returns string {
        log:printInfo("Payment service health check - HTTP service is running");
        return "Payment Service is running";
    }

    resource function post payments/process(ProcessPaymentRequest request) returns http:Created|http:BadRequest|http:InternalServerError {
        do {
            log:printInfo(string `Manual payment processing for ticket: ${request.ticketId}`);
            string paymentStatus = check processPayment(request.ticketId, request.userId, request.amount, request.paymentMethod);
            
            if paymentStatus == "COMPLETED" {
                return <http:Created>{
                    body: {
                        message: "Payment processed successfully",
                        paymentId: uuid:createType1AsString(),
                        status: paymentStatus
                    }
                };
            } else {
                return <http:BadRequest>{
                    body: {
                        message: "Payment failed",
                        paymentId: uuid:createType1AsString(),
                        status: paymentStatus,
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

        } on fail error e {
            log:printError("Error processing payment", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to process payment",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    resource function get payments/[string paymentId]() returns Payment|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection paymentsCollection = check db->getCollection("payments");

            map<json> query = { "id": paymentId };
            stream<record {}, error?> items = check paymentsCollection->find(query);

            Payment[] paymentArray = [];
            check items.forEach(function(record {} item) {
                Payment|error p = item.cloneWithType(Payment);
                if p is Payment {
                    paymentArray.push(p);
                }
            });

            if paymentArray.length() > 0 {
                return paymentArray[0];
            } else {
                return <http:NotFound>{};
            }

        } on fail error e {
            log:printError("Error fetching payment", 'error = e);
            return <http:InternalServerError>{};
        }
    }

    resource function get users/[string userId]/payments() returns Payment[]|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection paymentsCollection = check db->getCollection("payments");

            map<json> query = { "userId": userId };
            stream<record {}, error?> items = check paymentsCollection->find(query);

            Payment[] paymentArray = [];
            error? e = items.forEach(function(record {} item) {
                Payment|error p = item.cloneWithType(Payment);
                if p is Payment {
                    paymentArray.push(p);
                }
            });

            return paymentArray;

        } on fail error e {
            log:printError("Error fetching user payments", 'error = e);
            return <http:InternalServerError>{};
        }
    }
}


// Kafka Consumer Service  - BytesConsumerRecord for byte[] payloads
service on ticketRequestListener {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        log:printInfo(string `[KAFKA] Payment service received ${records.length()} records from ticket.requests`);

        // iterate safely; 'kRecord' is each BytesConsumerRecord
        foreach var kRecord in records {
            log:printInfo("[KAFKA] Processing record from ticket.requests...");

            byte[]? value = kRecord.value;
            if value is byte[] {
                string|error message = string:fromBytes(value);
                if message is string {
                    log:printInfo("[KAFKA] Raw message: " + message);

                    json|error jsonData = message.fromJsonString();
                    if jsonData is json {
                        TicketRequestEvent|error event = jsonData.cloneWithType(TicketRequestEvent);
                        if event is TicketRequestEvent {
                            log:printInfo(string `[KAFKA] Processing ticket: ${event.ticketId}, user: ${event.userId}, amount: ${event.price}`);

                            // process payment 
                            string|error result = processPayment(event.ticketId, event.userId, event.price, "AUTOMATIC_KAFKA");
                            if result is error {
                                log:printError(string `[KAFKA] Failed to process payment for ticket ${event.ticketId}`, 'error = result);
                            } else {
                                log:printInfo(string `[KAFKA] Successfully processed payment for ticket ${event.ticketId}, status: ${result}`);
                                // commit offsets after success; 'check' propagates errors and is allowed because this function returns error?
                                check caller->commit();
                            }
                        } else {
                            log:printError("[KAFKA] Failed to convert JSON to TicketRequestEvent", 'error = event);
                        }
                    } else {
                        log:printError("[KAFKA] Failed to parse message as JSON", 'error = jsonData);
                    }
                } else {
                    log:printError("[KAFKA] Failed to convert bytes to string", 'error = message);
                }
            } else {
                log:printError("[KAFKA] No value in Kafka record");
            }
        }

        return;
    }
}


// Initialize function with better logging
function init() returns error? {
    log:printInfo("=== PAYMENT SERVICE STARTING ===");
    log:printInfo(string `Kafka: ${kafkaBootstrapServers}`);
    log:printInfo(string `MongoDB: ${mongoHost}:${mongoPort}`);
    log:printInfo("Listening on topic: ticket.requests");
    log:printInfo("Group ID: payment-ticket-group");
    log:printInfo("=== PAYMENT SERVICE READY ===");
}