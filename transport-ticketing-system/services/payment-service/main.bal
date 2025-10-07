import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;
import ballerina/lang.runtime;

// Configuration
configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;
configurable string mongoUsername = "admin";
configurable string mongoPassword = "password123";
configurable string mongoDatabase = "transport_db";
configurable string kafkaBootstrapServers = "localhost:9092";

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
final kafka:Producer kafkaProducer = check new (kafka:DEFAULT_URL, {
    clientId: "payment-service-producer",
    acks: "all",
    retryCount: 3
});

// Kafka consumer for ticket requests
listener kafka:Listener ticketRequestConsumer = new (kafka:DEFAULT_URL, {
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

// Service implementation
service /payment on new http:Listener(9093) {
    
    resource function get health() returns string {
        return "Payment Service is running";
    }

    // Process payment manually (for testing)
    resource function post payments/process(ProcessPaymentRequest request) returns http:Created|http:BadRequest|http:InternalServerError {
        do {
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
                ticketId: request.ticketId,
                userId: request.userId,
                amount: request.amount,
                paymentMethod: request.paymentMethod,
                status: paymentStatus,
                transactionId: transactionId,
                createdAt: currentTime,
                completedAt: paymentSuccess ? currentTime : ()
            };

            check paymentsCollection->insertOne(newPayment);
            
            // Publish payment processed event
            PaymentProcessedEvent paymentEvent = {
                ticketId: request.ticketId,
                userId: request.userId,
                paymentId: paymentId,
                status: paymentStatus,
                amount: request.amount,
                timestamp: currentTime
            };

            check kafkaProducer->send({
                topic: "payments.processed",
                value: paymentEvent.toJsonString().toBytes()
            });

            log:printInfo(string `Payment processed: ${paymentId}, status: ${paymentStatus}`);
            
            if paymentSuccess {
                return <http:Created>{
                    body: {
                        message: "Payment processed successfully",
                        paymentId: paymentId,
                        transactionId: transactionId,
                        status: paymentStatus
                    }
                };
            } else {
                return <http:BadRequest>{
                    body: {
                        message: "Payment failed",
                        paymentId: paymentId,
                        status: paymentStatus,
                        timestamp: currentTime
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
// Get payment by ID
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
            } else {
                log:printError("Failed to convert record to Payment type", 'error = p);
            }
        });

        if paymentArray.length() > 0 {
            return paymentArray[0];
        } else {
            return <http:NotFound>{
                body: {
                    message: "Payment not found",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }

    } on fail error e {
        log:printError("Error fetching payment", 'error = e);
        return <http:InternalServerError>{
            body: {
                message: "Failed to fetch payment",
                timestamp: time:utcToString(time:utcNow())
            }
        };
    }
}

// Get payments by user
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
            } else {
                log:printError("Failed to convert record to Payment type", 'error = p);
            }
        });

        return paymentArray;

    } on fail error e {
        log:printError("Error fetching user payments", 'error = e);
        return <http:InternalServerError>{
            body: {
                message: "Failed to fetch payments",
                timestamp: time:utcToString(time:utcNow())
            }
        };
    }
}
}

