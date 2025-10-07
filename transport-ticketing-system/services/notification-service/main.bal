import ballerina/http;
import ballerina/log;
import ballerinax/kafka;
import ballerina/time;

// Configuration
configurable string kafkaBootstrapServers = "localhost:9092";

// Kafka consumers for different event types
listener kafka:Listener paymentConsumer = new (kafka:DEFAULT_URL, {
    groupId: "notification-payment-group",
    topics: ["payments.processed"]
});

listener kafka:Listener validationConsumer = new (kafka:DEFAULT_URL, {
    groupId: "notification-validation-group",
    topics: ["ticket.validated"]
});

listener kafka:Listener scheduleConsumer = new (kafka:DEFAULT_URL, {
    groupId: "notification-schedule-group",
    topics: ["schedule.updates"]
});

// Types
public type PaymentProcessedEvent record {|
    string ticketId;
    string userId;
    string paymentId;
    string status;
    decimal amount;
    string timestamp;
|};

public type TicketValidatedEvent record {|
    string ticketId;
    string userId;
    string tripId?;
    string validatedBy;
    string timestamp;
|};

public type ScheduleUpdateEvent record {|
    string routeId;
    string tripId?;
    string updateType;
    string message;
    string timestamp;
|};

// Notification functions
function sendNotification(string userId, string notificationType, string title, string message) {
    // In production, this would send SMS, email, push notification, etc.
    string logMessage = "╔════════════════════════════════════════════════════════\n";
    logMessage = logMessage + "║ NOTIFICATION\n";
    logMessage = logMessage + "╠════════════════════════════════════════════════════════\n";
    logMessage = logMessage + "║ User ID: " + userId + "\n";
    logMessage = logMessage + "║ Type: " + notificationType + "\n";
    logMessage = logMessage + "║ Title: " + title + "\n";
    logMessage = logMessage + "║ Message: " + message + "\n";
    logMessage = logMessage + "║ Time: " + time:utcToString(time:utcNow()) + "\n";
    logMessage = logMessage + "╚════════════════════════════════════════════════════════";
    
    log:printInfo(logMessage);
}

// Service implementation
service /notification on new http:Listener(9094) {
    
    resource function get health() returns string {
        return "Notification Service is running";
    }

    // Manual notification endpoint (for testing)
    resource function post send(record {| string userId; string title; string message; |} request) returns http:Ok {
        sendNotification(request.userId, "MANUAL", request.title, request.message);
        return <http:Ok>{
            body: {
                message: "Notification sent",
                timestamp: time:utcToString(time:utcNow())
            }
        };
    }
}

// Payment event consumer
service on paymentConsumer {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            byte[] value = rec.value;
            string payload = check string:fromBytes(value);
            json paymentEvent = check payload.fromJsonString();
            
            PaymentProcessedEvent event = check paymentEvent.cloneWithType(PaymentProcessedEvent);
            
            if event.status == "COMPLETED" {
                string message = "Your payment of N$" + event.amount.toString() + " for ticket " + event.ticketId + " was successful. Transaction ID: " + event.paymentId;
                sendNotification(
                    event.userId,
                    "PAYMENT_SUCCESS",
                    "Payment Successful",
                    message
                );
            } else {
                string message = "Your payment for ticket " + event.ticketId + " failed. Please try again.";
                sendNotification(
                    event.userId,
                    "PAYMENT_FAILED",
                    "Payment Failed",
                    message
                );
            }
        }
    }
}

// Ticket validation event consumer
service on validationConsumer {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            byte[] value = rec.value;
            string payload = check string:fromBytes(value);
            json validationEvent = check payload.fromJsonString();
            
            TicketValidatedEvent event = check validationEvent.cloneWithType(TicketValidatedEvent);
            
            string message = "";
            string tripMessage = "";  
            
            if event.tripId is string {
                tripMessage = "Trip: " + <string>event.tripId;
            } else {
                tripMessage = "All trips";
            }

            sendNotification(
                event.userId,
                "TICKET_VALIDATED",
                "Ticket Validated",
                message
            );
        }
    }
}


// Schedule update event consumer
service on scheduleConsumer {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            byte[] value = rec.value;
            string payload = check string:fromBytes(value);
            json scheduleEvent = check payload.fromJsonString();
            
            ScheduleUpdateEvent event = check scheduleEvent.cloneWithType(ScheduleUpdateEvent);
            
            string notificationType = "SCHEDULE_UPDATE";
            string title = "Service Update";
            string tripMessage = "";  
            
            match event.updateType {
                "DELAYED" => {
                    notificationType = "TRIP_DELAYED";
                    title = "Trip Delayed";
                }
                "CANCELLED" => {
                    notificationType = "TRIP_CANCELLED";
                    title = "Trip Cancelled";
                }
                _ => {}
            }
            
            if event.tripId is string {
                tripMessage = "Trip: " + <string>event.tripId;
            } else {
                tripMessage = "All trips";
            }

            string logMessage = "╔════════════════════════════════════════════════════════\n";
            logMessage = logMessage + "║ BROADCAST NOTIFICATION\n";
            logMessage = logMessage + "╠════════════════════════════════════════════════════════\n";
            logMessage = logMessage + "║ Type: " + notificationType + "\n";
            logMessage = logMessage + "║ Title: " + title + "\n";
            logMessage = logMessage + "║ Route: " + event.routeId + "\n";
            logMessage = logMessage + "║ " + tripMessage + "\n";
            logMessage = logMessage + "║ Message: " + event.message + "\n";
            logMessage = logMessage + "║ Time: " + event.timestamp + "\n";
            logMessage = logMessage + "╚════════════════════════════════════════════════════════";
            
            log:printInfo(logMessage);
        }
    }
}
