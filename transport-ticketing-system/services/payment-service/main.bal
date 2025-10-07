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

// Kafka consumer for ticket requests - FIXED CONFIGURATION
listener kafka:Listener ticketRequestConsumer = new (kafkaBootstrapServers, {
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
        return "Payment Service is running";
    }

    resource function post payments/process(ProcessPaymentRequest request) returns http:Created|http:BadRequest|http:InternalServerError {
        do {
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
            error? e = items.forEach(function(record {} item) {
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

// Kafka Consumer Service - SIMPLIFIED AND FIXED
service on ticketRequestConsumer {
    remote function onConsumerRecord(kafka:Caller caller, kafka:ConsumerRecord[] records) returns error? {
        foreach var {value} in records {
            if value is byte[] {
                string message = check string:fromBytes(value);
                log:printInfo("Received Kafka message: " + message);
                
                json jsonMessage = check message.fromJsonString();
                TicketRequestEvent event = check jsonMessage.cloneWithType(TicketRequestEvent);

                log:printInfo(string `Processing ticket payment request: ${event.ticketId} for user: ${event.userId}, amount: ${event.price}`);
                
                // Process the payment
                _ = processPayment(event.ticketId, event.userId, event.price, "AUTOMATIC_KAFKA");
            }
        }
        return;
    }
}