import ballerina/http;
import ballerina/log;
import ballerina/email;
import ballerina/time;
import ballerina/uuid;
import ballerina/os;
import ballerina/lang.runtime;
import ballerinax/kafka;
import ballerinax/mongodb;

// Configuration for MongoDB connection
configurable string mongoHost = os:getEnv("MONGO_HOST") != "" ? os:getEnv("MONGO_HOST") : "localhost";
configurable int mongoPort = os:getEnv("MONGO_PORT") != "" ? check int:fromString(os:getEnv("MONGO_PORT")) : 27017;
configurable string databaseName = os:getEnv("MONGO_DATABASE") != "" ? os:getEnv("MONGO_DATABASE") : "transport_db";

string mongodbUrl = string `mongodb://${mongoHost}:${mongoPort}`;

// Configuration for Kafka
configurable string kafkaBootstrapServers = os:getEnv("KAFKA_BOOTSTRAP_SERVERS") != "" ? os:getEnv("KAFKA_BOOTSTRAP_SERVERS") : "localhost:9092";

// Email configuration
configurable string smtpHost = "smtp.gmail.com";
configurable int smtpPort = 587;
configurable string smtpUser = "noreply@transport.com";
configurable string smtpPassword = "your-app-password";

// SMS configuration (simulate for demo)
configurable string smsApiKey = "your-sms-api-key";

// MongoDB client for database operations
mongodb:Client mongoClient = check new (mongodbUrl, database = databaseName);

// Kafka consumer for notification events
kafka:ConsumerConfiguration kafkaConsumerConfig = {
    bootstrapServers: kafkaBootstrapServers,
    groupId: "notification-service-group",
    topics: [
        "user.events",
        "ticket.validations", 
        "payments.processed",
        "schedule.updates",
        "notification.triggers"
    ],
    autoOffsetReset: kafka:OFFSET_RESET_EARLIEST
};

kafka:Consumer kafkaConsumer = check new (kafkaConsumerConfig);

// Email client for sending emails
email:SmtpClient smtpClient = check new ({
    host: smtpHost,
    port: smtpPort,
    username: smtpUser,
    password: smtpPassword
});

// Define notification record types
type Notification record {
    string id?;
    string notificationId;
    string userId;
    string notificationType;
    string channel;
    string subject;
    string content;
    string status;
    string sentAt?;
    string failureReason?;
    map<json> metadata?;
    string createdAt;
    string updatedAt;
};

type NotificationTemplate record {
    string templateId;
    string templateType;
    string subject;
    string contentTemplate;
    string[] requiredFields;
};

type UserNotificationPreferences record {
    string userId;
    boolean emailEnabled;
    boolean smsEnabled;
    boolean pushEnabled;
    string email?;
    string phoneNumber?;
};

type BulkNotificationRequest record {
    string[] userIds;
    string subject;
    string content;
    string[] channels;
};

// Notification templates
map<NotificationTemplate> templates = {
    "WELCOME": {
        templateId: "WELCOME",
        templateType: "USER_REGISTRATION",
        subject: "Welcome to Smart Transport System",
        contentTemplate: "Dear {fullName},\n\nWelcome to the Smart Transport System! Your account has been created successfully.\n\nUsername: {username}\n\nYou can now purchase tickets and enjoy seamless travel across our network.\n\nBest regards,\nSmart Transport Team",
        requiredFields: ["fullName", "username"]
    },
    "TICKET_PURCHASE": {
        templateId: "TICKET_PURCHASE",
        templateType: "TICKET_PURCHASE",
        subject: "Ticket Purchase Confirmation",
        contentTemplate: "Dear {userName},\n\nYour ticket purchase has been confirmed!\n\nTicket ID: {ticketId}\nType: {ticketType}\nValid From: {validFrom}\nValid Until: {validUntil}\nAmount Paid: NAD {amount}\n\nPlease keep this ticket ID for your reference.\n\nSafe travels!",
        requiredFields: ["userName", "ticketId", "ticketType", "validFrom", "validUntil", "amount"]
    },
    "PAYMENT_SUCCESS": {
        templateId: "PAYMENT_SUCCESS",
        templateType: "PAYMENT",
        subject: "Payment Successful",
        contentTemplate: "Dear Customer,\n\nYour payment has been processed successfully.\n\nPayment ID: {paymentId}\nAmount: NAD {amount}\nTicket ID: {ticketId}\nTimestamp: {timestamp}\n\nThank you for using Smart Transport System!",
        requiredFields: ["paymentId", "amount", "ticketId", "timestamp"]
    },
    "SERVICE_DISRUPTION": {
        templateId: "SERVICE_DISRUPTION",
        templateType: "DISRUPTION",
        subject: "Service Disruption Alert",
        contentTemplate: "Dear Passenger,\n\nWe regret to inform you about a service disruption:\n\n{title}\n\n{description}\n\nAffected Routes: {affectedRoutes}\nEstimated Duration: {duration}\n\nWe apologize for the inconvenience.\n\nFor updates, please check our app or website.",
        requiredFields: ["title", "description", "affectedRoutes", "duration"]
    },
    "TRIP_DELAY": {
        templateId: "TRIP_DELAY",
        templateType: "DELAY",
        subject: "Trip Delay Notification",
        contentTemplate: "Dear Passenger,\n\nYour trip {tripId} on route {routeId} is delayed by {delayMinutes} minutes.\n\nNew departure time: {newDepartureTime}\n\nWe apologize for the inconvenience.",
        requiredFields: ["tripId", "routeId", "delayMinutes", "newDepartureTime"]
    }
};
service /notification on new http:Listener(8085) {

    isolated remote function init() returns error? {
        _ = start consumeKafkaEvents();
        log:printInfo("Notification service started and listening to Kafka events");
    }

    resource function post send(http:Caller caller, http:Request req) returns json|error {
        json request = check req.getJsonPayload();
        string userId = check request.userId.ensureType(string);
        string subject = check request.subject.ensureType(string);
        string content = check request.content.ensureType(string);
        string channel = check request.channel.ensureType(string);

        UserNotificationPreferences|error prefResult = getUserPreferences(userId);
        if prefResult is error {
            return { "error": "User not found or notification preferences not set" };
        }
        UserNotificationPreferences preferences = <UserNotificationPreferences>prefResult;

        boolean success = false;
        string notificationId = "NOTIF-" + uuid:createType1AsString().substring(0, 12).toUpperAscii();

        if channel == "EMAIL" && preferences.emailEnabled {
            success = check sendEmailNotification(preferences.email ?: "", subject, content);
        } else if channel == "SMS" && preferences.smsEnabled {
            success = check sendSmsNotification(preferences.phoneNumber ?: "", content);
        } else if channel == "PUSH" && preferences.pushEnabled {
            success = check sendPushNotification(userId, subject, content);
        }

        check storeNotification(notificationId, userId, "MANUAL", channel, subject, content, success);

        return {
            "notificationId": notificationId,
            "status": success ? "sent" : "failed",
            "channel": channel,
            "timestamp": time:utcToString(time:utcNow())
        };
    }

    resource function post bulk(http:Caller caller, http:Request req) returns json|error {
        json request = check req.getJsonPayload();
        int successCount = 0;
        int failureCount = 0;

        string[] userIds = check request.userIds.ensureType(string[]);
        string subject = check request.subject.ensureType(string);
        string content = check request.content.ensureType(string);
        string[] channels = check request.channels.ensureType(string[]);

        foreach string userId in userIds {
            UserNotificationPreferences|error prefResult = getUserPreferences(userId);
            if prefResult is UserNotificationPreferences {
                UserNotificationPreferences preferences = <UserNotificationPreferences>prefResult;
                foreach string channel in channels {
                    boolean success = false;

                    if channel == "EMAIL" && preferences.emailEnabled {
                        success = check sendEmailNotification(
                            preferences.email ?: "",
                            subject,
                            content
                        );
                    } else if channel == "SMS" && preferences.smsEnabled {
                        success = check sendSmsNotification(
                            preferences.phoneNumber ?: "",
                            content
                        );
                    }

                    if success {
                        successCount += 1;
                    } else {
                        failureCount += 1;
                    }
                }
            }
        }

        return {
            "totalRecipients": userIds.length(),
            "successCount": successCount,
            "failureCount": failureCount,
            "timestamp": time:utcToString(time:utcNow())
        };
    }

    resource function get users/[string userId]/history(http:Caller caller, http:Request req) returns json|error {
        string? status = req.getQueryParam("status");
        int limit = check req.getQueryParam("limit").ensureType(int) ?: 50;

        mongodb:Collection notificationsCollection = check mongoClient.getCollection("notifications");

        map<anydata> query = { "userId": userId };
        if status is string {
            query["status"] = status;
        }

        stream<map<anydata>, error?> notificationsStream = check notificationsCollection.find(query);

        Notification[] notifications = [];
        int count = 0;
        check from map<anydata> notification in notificationsStream
            do {
                if count < limit {
                    notifications.push(<Notification>notification);
                    count += 1;
                }
            };

        return notifications;
    }

    resource function put users/[string userId]/preferences(http:Caller caller, http:Request req) returns json|error {
        json prefJson = check req.getJsonPayload();
        UserNotificationPreferences preferences = check prefJson.cloneWithType(UserNotificationPreferences);

        mongodb:Collection preferencesCollection = check mongoClient.getCollection("notificationPreferences");

        map<anydata> filter = { "userId": userId };
        map<anydata> update = {
            "$set": {
                "emailEnabled": preferences.emailEnabled,
                "smsEnabled": preferences.smsEnabled,
                "pushEnabled": preferences.pushEnabled,
                "email": preferences.email,
                "phoneNumber": preferences.phoneNumber,
                "updatedAt": time:utcToString(time:utcNow())
            }
        };

        check preferencesCollection.updateOne(filter, update, { upsert: true });

        return {
            "message": "Notification preferences updated successfully",
            "userId": userId,
            "preferences": preferences
        };
    }

    resource function get templates(http:Caller caller, http:Request req) returns json|error {
        string? type = req.getQueryParam("type");
        if type is string && templates.hasKey(type) {
            return templates[type];
        }

        NotificationTemplate[] allTemplates = [];
        foreach var [_, template] in templates.entries() {
            allTemplates.push(template);
        }
        return allTemplates;
    }

    resource function get health(http:Caller caller, http:Request req) returns json {
        return {
            "service": "notification-service",
            "status": "healthy",
            "timestamp": time:utcToString(time:utcNow())
        };
    }
}
            "status": "healthy",
            "timestamp": time:utcToString(time:utcNow())
        };
    }
function consumeKafkaEvents() returns error? {
    while true {
        kafka:ConsumerRecord[] records = check kafkaConsumer.poll(1000);

        foreach kafka:ConsumerRecord kafkaRecord in records {
            byte[] value = kafkaRecord.value;
            string messageStr = check string:fromBytes(value);
            json message = check messageStr.fromJsonString();

            string eventType = check message.eventType;

            if kafkaRecord.topic == "user.events" {
                check handleUserEvents(eventType, message);
            } else if kafkaRecord.topic == "payments.processed" {
                check handlePaymentEvents(eventType, message);
            } else if kafkaRecord.topic == "ticket.validations" {
                check handleTicketValidation(eventType, message);
            } else if kafkaRecord.topic == "schedule.updates" {
                check handleScheduleUpdates(eventType, message);
            } else if kafkaRecord.topic == "notification.triggers" {
                check handleNotificationTrigger(message);
            }
        }

        check kafkaConsumer.commit();
    }
}
        check kafkaConsumer->commit();
    }
function handleUserEvents(string eventType, json message) returns error? {
    if eventType == "USER_REGISTERED" {
        string userId = check message.userId;
        string username = check message.username;
        string email = check message.email;

        // Use template for welcome email
        NotificationTemplate welcomeTemplate = templates["WELCOME"];
        string content = welcomeTemplate.contentTemplate.replace("{fullName}", username).replace("{username}", username);

        boolean sent = check sendEmailNotification(email, welcomeTemplate.subject, content);

        if sent {
            log:printInfo("Welcome notification sent to: " + username);
        }
    }
}
        }
    }
}

function handlePaymentEvents(string eventType, json message) returns error? {
    if eventType == "PAYMENT_COMPLETED" {
        string userId = check message.userId;
        string paymentId = check message.paymentId;
        string ticketId = check message.ticketId;
        decimal amount = check message.amount.ensureType();

        UserNotificationPreferences|error prefResult = getUserPreferences(userId);
        if prefResult is UserNotificationPreferences {
            UserNotificationPreferences preferences = <UserNotificationPreferences>prefResult;
            if preferences.emailEnabled {
                NotificationTemplate template = templates["PAYMENT_SUCCESS"];
                string content = template.contentTemplate
                    .replace("{paymentId}", paymentId)
                    .replace("{amount}", amount.toString())
                    .replace("{ticketId}", ticketId)
                    .replace("{timestamp}", time:utcToString(time:utcNow()));
                boolean sent = check sendEmailNotification(
                    preferences.email ?: "",
                    template.subject,
                    content
                );

                if sent {
                    log:printInfo("Payment confirmation sent for: " + paymentId);
                }
            }
        }
function handleTicketValidation(string eventType, json message) returns error? {
    if eventType == "TICKET_VALIDATED" {
        string userId = check message.userId;
        string ticketId = check message.ticketId;
        string location = check message.location;

        // Send push notification for validation
        string title = "Ticket Validated";
        string content = "Your ticket " + ticketId + " has been validated at " + location;

        boolean _ = check sendPushNotification(userId, title, content);
        log:printInfo("Validation notification sent for ticket: " + ticketId);
    }
}
        
        check sendPushNotification(userId, title, content);
function handleScheduleUpdates(string eventType, json message) returns error? {
    if eventType == "SERVICE_DISRUPTION" {
        string title = check message.title;
        string description = check message.description;
        json affectedRoutes = check message.affectedRoutes;

        // Get all affected users (those with tickets for affected routes)
        string[] affectedUserIds = check getAffectedUsers(affectedRoutes);

        NotificationTemplate template = templates["SERVICE_DISRUPTION"];
        string content = template.contentTemplate
            .replace("{title}", title)
            .replace("{description}", description)
            .replace("{affectedRoutes}", affectedRoutes.toString())
            .replace("{duration}", "Check app for updates");

        // Send notifications to all affected users
        foreach string userId in affectedUserIds {
            UserNotificationPreferences|error prefResult = getUserPreferences(userId);
            if prefResult is UserNotificationPreferences {
                UserNotificationPreferences preferences = <UserNotificationPreferences>prefResult;
                if preferences.emailEnabled {
                    boolean _ = check sendEmailNotification(
                        preferences.email ?: "",
                        template.subject,
                        content
                    );
                }
                if preferences.pushEnabled {
                    boolean _ = check sendPushNotification(userId, template.subject, description);
                }
            }
        }

        log:printInfo("Disruption notifications sent for: " + title);

    } else if eventType == "TRIP_STATUS_UPDATED" {
        string tripId = check message.tripId;
        string newStatus = check message.newStatus;
        int? delayMinutes = check message.delayMinutes;

        if newStatus == "DELAYED" && delayMinutes is int {
            // Notify passengers about delay
            string[] affectedUserIds = check getUsersForTrip(tripId);

            NotificationTemplate template = templates["TRIP_DELAY"];
            string content = template.contentTemplate
                .replace("{tripId}", tripId)
                .replace("{routeId}", check message.routeId)
                .replace("{delayMinutes}", delayMinutes.toString())
                .replace("{newDepartureTime}", "Check app for updates");

            foreach string userId in affectedUserIds {
                UserNotificationPreferences|error prefResult = getUserPreferences(userId);
                if prefResult is UserNotificationPreferences {
                    UserNotificationPreferences preferences = <UserNotificationPreferences>prefResult;
                    if preferences.pushEnabled {
                        boolean _ = check sendPushNotification(userId, template.subject, content);
                    }
                }
            }
        }
    }
}
                }
            }
        }
    }
function sendEmailNotification(string toEmail, string subject, string content) returns boolean|error {
    if toEmail.length() == 0 {
        return false;
    }

    email:Message emailMessage = {
        to: toEmail,
        subject: subject,
        body: content,
        from: smtpUser
    };

    error? result = smtpClient->sendMessage(emailMessage);

    if result is error {
        log:printError("Failed to send email: " + result.message());
        return false;
    }

    return true;
}
    email:Error? result = smtpClient->sendMessage(emailMessage);
    
    if result is email:Error {
        log:printError("Failed to send email: " + result.message());
        return false;
    }
    
    return true;
}

// Helper function to send SMS notification (simulated)
function sendSmsNotification(string phoneNumber, string message) returns boolean|error {
    if phoneNumber.length() == 0 {
        return false;
    }
    
    // In production, integrate with actual SMS provider
    log:printInfo("SMS sent to " + phoneNumber + ": " + message);
    
    // Simulate API call delay
    runtime:sleep(0.1);
    
    return true;
}

// Helper function to send push notification (simulated)
function sendPushNotification(string userId, string title, string message) returns boolean|error {
    // In production, integrate with FCM/APNS
    log:printInfo("Push notification sent to user " + userId + " - Title: " + title);
    
    // Store in database for app to retrieve
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection pushNotificationsCollection = check db->getCollection("pushNotifications");
    
    map<json> notification = {
        "userId": userId,
        "title": title,
        "message": message,
        "read": false,
        "createdAt": time:utcToString(time:utcNow())
    };
    
    check pushNotificationsCollection->insertOne(notification);
    
    return true;
}

// Helper function to store notification in database
function storeNotification(string notificationId, string userId, string notificationType, 
                          string channel, string subject, string content, boolean success) returns error? {
    // Use the MongoDB client directly for collection operations
    Notification notification = {
        notificationId: notificationId,
        userId: userId,
        notificationType: notificationType,
        channel: channel,
        subject: subject,
        content: content,
        status: success ? "SENT" : "FAILED",
        sentAt: success ? time:utcToString(time:utcNow()) : (),
        createdAt: time:utcToString(time:utcNow()),
function getUserPreferences(string userId) returns UserNotificationPreferences|error {
    mongodb:Collection usersCollection = check mongoClient.getCollection("users");

    map<anydata> query = { "id": userId };
    stream<map<anydata>, error?> users = check usersCollection.find(query);

    map<anydata>? user = check users.next();
    if user is map<anydata> {
        map<anydata>? notifications = user.hasKey("notifications") ? <map<anydata>>user["notifications"] : ();
        boolean emailEnabled = notifications is map<anydata> && notifications.hasKey("email") ? <boolean>notifications["email"] : false;
        boolean smsEnabled = notifications is map<anydata> && notifications.hasKey("sms") ? <boolean>notifications["sms"] : false;
        boolean pushEnabled = notifications is map<anydata> && notifications.hasKey("push") ? <boolean>notifications["push"] : false;
        string email = user.hasKey("email") ? <string>user["email"] : "";
        string phoneNumber = user.hasKey("phoneNumber") ? <string>user["phoneNumber"] : "";

        return {
            userId: userId,
            emailEnabled: emailEnabled,
            smsEnabled: smsEnabled,
            pushEnabled: pushEnabled,
            email: email,
            phoneNumber: phoneNumber
        };
function getAffectedUsers(json affectedRoutes) returns string[]|error {
    mongodb:Collection ticketsCollection = check mongoClient.getCollection("tickets");

    // Find all active tickets for affected routes
    map<anydata> query = {
        "tripDetails.routeId": { "$in": affectedRoutes },
        "status": { "$in": ["PAID", "VALIDATED"] }
    };

    stream<map<anydata>, error?> tickets = check ticketsCollection.find(query);

    string[] userIds = [];
    map<boolean> uniqueUsers = {};

    check from map<anydata> ticket in tickets
        do {
            string userId = ticket.hasKey("userId") ? <string>ticket["userId"] : "";
            if userId != "" && !uniqueUsers.hasKey(userId) {
                userIds.push(userId);
                uniqueUsers[userId] = true;
            }
        };

    return userIds;
}
    
    string[] userIds = [];
    map<boolean> uniqueUsers = {};
function getUsersForTrip(string tripId) returns string[]|error {
    mongodb:Collection ticketsCollection = check mongoClient.getCollection("tickets");

    map<anydata> query = {
        "tripDetails.tripId": tripId,
        "status": { "$in": ["PAID", "VALIDATED"] }
    };

    stream<map<anydata>, error?> tickets = check ticketsCollection.find(query);

    string[] userIds = [];
    check from map<anydata> ticket in tickets
        do {
            string userId = ticket.hasKey("userId") ? <string>ticket["userId"] : "";
            if userId != "" {
                userIds.push(userId);
            }
        };

    return userIds;
}       "tripDetails.tripId": tripId,
        "status": {"$in": ["PAID", "VALIDATED"]}
    };
    
    stream<map<json>, error?> tickets = check ticketsCollection->find(query);
    
    string[] userIds = [];
    check from map<json> ticket in tickets
        do {
            string userId = check ticket["userId"].ensureType(string);
            userIds.push(userId);
        };
    
    return userIds;
}