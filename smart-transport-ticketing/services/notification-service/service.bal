import ballerina/http;
import ballerina/log;
import ballerina/email;
import ballerina/time;
import ballerinax/kafka;
import ballerinax/mongodb;

// Configuration for MongoDB connection
configurable string mongodbUrl = "mongodb://localhost:27017";
configurable string databaseName = "transport_ticketing";

// Configuration for Kafka
configurable string kafkaBootstrapServers = "localhost:9092";

// Email configuration
configurable string smtpHost = "smtp.gmail.com";
configurable int smtpPort = 587;
configurable string smtpUser = "noreply@transport.com";
configurable string smtpPassword = "your-app-password";

// SMS configuration (simulate for demo)
configurable string smsApiKey = "your-sms-api-key";

// MongoDB client for database operations
mongodb:Client mongoClient = check new (mongodbUrl);

// Kafka consumer for notification events
kafka:Consumer kafkaConsumer = check new ({
    bootstrapServers: kafkaBootstrapServers,
    groupId: "notification-service-group",
    topics: [
        "user.events",
        "ticket.validations", 
        "payments.processed",
        "schedule.updates",
        "notification.triggers"
    ],
    autoOffsetReset: "earliest"
});

// Email client for sending emails
email:SmtpClient smtpClient = check new (smtpHost, smtpUser, smtpPassword, smtpPort);

// Define notification record types
type Notification record {
    string id?;
    string notificationId;
    string userId;
    string type;
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
    string type;
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
        type: "USER_REGISTRATION",
        subject: "Welcome to Smart Transport System",
        contentTemplate: "Dear {fullName},\n\nWelcome to the Smart Transport System! Your account has been created successfully.\n\nUsername: {username}\n\nYou can now purchase tickets and enjoy seamless travel across our network.\n\nBest regards,\nSmart Transport Team",
        requiredFields: ["fullName", "username"]
    },
    "TICKET_PURCHASE": {
        templateId: "TICKET_PURCHASE",
        type: "TICKET_PURCHASE",
        subject: "Ticket Purchase Confirmation",
        contentTemplate: "Dear {userName},\n\nYour ticket purchase has been confirmed!\n\nTicket ID: {ticketId}\nType: {ticketType}\nValid From: {validFrom}\nValid Until: {validUntil}\nAmount Paid: NAD {amount}\n\nPlease keep this ticket ID for your reference.\n\nSafe travels!",
        requiredFields: ["userName", "ticketId", "ticketType", "validFrom", "validUntil", "amount"]
    },
    "PAYMENT_SUCCESS": {
        templateId: "PAYMENT_SUCCESS",
        type: "PAYMENT",
        subject: "Payment Successful",
        contentTemplate: "Dear Customer,\n\nYour payment has been processed successfully.\n\nPayment ID: {paymentId}\nAmount: NAD {amount}\nTicket ID: {ticketId}\nTimestamp: {timestamp}\n\nThank you for using Smart Transport System!",
        requiredFields: ["paymentId", "amount", "ticketId", "timestamp"]
    },
    "SERVICE_DISRUPTION": {
        templateId: "SERVICE_DISRUPTION",
        type: "DISRUPTION",
        subject: "Service Disruption Alert",
        contentTemplate: "Dear Passenger,\n\nWe regret to inform you about a service disruption:\n\n{title}\n\n{description}\n\nAffected Routes: {affectedRoutes}\nEstimated Duration: {duration}\n\nWe apologize for the inconvenience.\n\nFor updates, please check our app or website.",
        requiredFields: ["title", "description", "affectedRoutes", "duration"]
    },
    "TRIP_DELAY": {
        templateId: "TRIP_DELAY",
        type: "DELAY",
        subject: "Trip Delay Notification",
        contentTemplate: "Dear Passenger,\n\nYour trip {tripId} on route {routeId} is delayed by {delayMinutes} minutes.\n\nNew departure time: {newDepartureTime}\n\nWe apologize for the inconvenience.",
        requiredFields: ["tripId", "routeId", "delayMinutes", "newDepartureTime"]
    }
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

# A service representing a network-accessible API
# bound to port `9090`.
service / on new http:Listener(9090) {

    // Initialize Kafka consumer listener on startup
    function init() returns error? {
        _ = start consumeKafkaEvents();
        log:printInfo("Notification service started and listening to Kafka events");
    }
    
    // Send notification manually
    resource function post send(@http:Payload map<json> request) 
            returns map<json>|http:BadRequest|http:InternalServerError {
        string userId = check request["userId"].ensureType();
        string subject = check request["subject"].ensureType();
        string content = check request["content"].ensureType();
        string channel = check request["channel"].ensureType();
        
        // Get user preferences and contact info
        UserNotificationPreferences? preferences = check getUserPreferences(userId);
        if preferences is () {
            return <http:BadRequest>{
                body: {"error": "User not found or notification preferences not set"}
            };
        }
        
        boolean success = false;
        string notificationId = "NOTIF-" + uuid:createType1AsString().substring(0, 12).toUpperAscii();
        
        if channel == "EMAIL" && preferences.emailEnabled {
            success = check sendEmailNotification(preferences.email ?: "", subject, content);
        } else if channel == "SMS" && preferences.smsEnabled {
            success = check sendSmsNotification(preferences.phoneNumber ?: "", content);
        } else if channel == "PUSH" && preferences.pushEnabled {
            success = check sendPushNotification(userId, subject, content);
        }
        
        // Store notification in database
        check storeNotification(notificationId, userId, "MANUAL", channel, subject, content, success);
        
        return {
            "notificationId": notificationId,
            "status": success ? "sent" : "failed",
            "channel": channel,
            "timestamp": time:utcToString(time:utcNow())
        };
    }
    
    // Send bulk notifications
    resource function post bulk(@http:Payload BulkNotificationRequest request) 
            returns map<json>|http:InternalServerError {
        int successCount = 0;
        int failureCount = 0;
        
        foreach string userId in request.userIds {
            UserNotificationPreferences? preferences = check getUserPreferences(userId);
            if preferences is UserNotificationPreferences {
                foreach string channel in request.channels {
                    boolean success = false;
                    
                    if channel == "EMAIL" && preferences.emailEnabled {
                        success = check sendEmailNotification(
                            preferences.email ?: "", 
                            request.subject, 
                            request.content
                        );
                    } else if channel == "SMS" && preferences.smsEnabled {
                        success = check sendSmsNotification(
                            preferences.phoneNumber ?: "", 
                            request.content
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
            "totalRecipients": request.userIds.length(),
            "successCount": successCount,
            "failureCount": failureCount,
            "timestamp": time:utcToString(time:utcNow())
        };
    }
    
    // Get notification history for a user
    resource function get users/[string userId]/history(string? status = (), int limit = 50) 
            returns Notification[]|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection notificationsCollection = check db->getCollection("notifications");
        
        map<json> query = {"userId": userId};
        if status is string {
            query["status"] = status;
        }
        
        stream<Notification, error?> notificationsStream = check notificationsCollection->find(query);
        
        Notification[] notifications = [];
        int count = 0;
        check from Notification notification in notificationsStream
            do {
                if count < limit {
                    notifications.push(notification);
                    count += 1;
                }
            };
        
        return notifications;
    }
    
    // Update user notification preferences
    resource function put users/[string userId]/preferences(@http:Payload UserNotificationPreferences preferences) 
            returns map<json>|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection preferencesCollection = check db->getCollection("notificationPreferences");
        
        map<json> filter = {"userId": userId};
        map<json> update = {
            "$set": {
                "emailEnabled": preferences.emailEnabled,
                "smsEnabled": preferences.smsEnabled,
                "pushEnabled": preferences.pushEnabled,
                "email": preferences.email,
                "phoneNumber": preferences.phoneNumber,
                "updatedAt": time:utcToString(time:utcNow())
            }
        };
        
        mongodb:UpdateResult result = check preferencesCollection->updateOne(filter, update, {upsert: true});
        
        return {
            "message": "Notification preferences updated successfully",
            "userId": userId,
            "preferences": preferences
        };
    }
    
    // Get notification templates
    resource function get templates(string? type = ()) returns NotificationTemplate[]|NotificationTemplate {
        if type is string {
            if templates.hasKey(type) {
                return templates.get(type);
            }
        }
        
        NotificationTemplate[] allTemplates = [];
        foreach NotificationTemplate template in templates {
            allTemplates.push(template);
        }
        return allTemplates;
    }
    
    // Health check endpoint
    resource function get health() returns map<json> {
        return {
            "service": "notification-service",
            "status": "healthy",
            "timestamp": time:utcToString(time:utcNow())
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
        
        check kafkaConsumer->commit();
    }
}

// Handle user events
function handleUserEvents(string eventType, json message) returns error? {
    if eventType == "USER_REGISTERED" {
        string userId = check message.userId;
        string username = check message.username;
        string email = check message.email;
        
        // Use template for welcome email
        NotificationTemplate welcomeTemplate = templates.get("WELCOME");
        string content = welcomeTemplate.contentTemplate
            .replace("{fullName}", username)
            .replace("{username}", username);
        
        boolean sent = check sendEmailNotification(email, welcomeTemplate.subject, content);
        
        if sent {
            log:printInfo("Welcome notification sent to: " + username);
        }
    }
}

// Handle payment events
function handlePaymentEvents(string eventType, json message) returns error? {
    if eventType == "PAYMENT_COMPLETED" {
        string userId = check message.userId;
        string paymentId = check message.paymentId;
        string ticketId = check message.ticketId;
        decimal amount = check message.amount.ensureType();
        
        UserNotificationPreferences? preferences = check getUserPreferences(userId);
        if preferences is UserNotificationPreferences && preferences.emailEnabled {
            NotificationTemplate template = templates.get("PAYMENT_SUCCESS");
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
}

// Handle ticket validation
function handleTicketValidation(string eventType, json message) returns error? {
    if eventType == "TICKET_VALIDATED" {
        string userId = check message.userId;
        string ticketId = check message.ticketId;
        string location = check message.location;
        
        // Send push notification for validation
        string title = "Ticket Validated";
        string content = "Your ticket " + ticketId + " has been validated at " + location;
        
        check sendPushNotification(userId, title, content);
        log:printInfo("Validation notification sent for ticket: " + ticketId);
    }
}

// Handle schedule updates
function handleScheduleUpdates(string eventType, json message) returns error? {
    if eventType == "SERVICE_DISRUPTION" {
        string title = check message.title;
        string description = check message.description;
        json affectedRoutes = check message.affectedRoutes;
        
        // Get all affected users (those with tickets for affected routes)
        string[] affectedUserIds = check getAffectedUsers(affectedRoutes);
        
        NotificationTemplate template = templates.get("SERVICE_DISRUPTION");
        string content = template.contentTemplate
            .replace("{title}", title)
            .replace("{description}", description)
            .replace("{affectedRoutes}", affectedRoutes.toString())
            .replace("{duration}", "Check app for updates");
        
        // Send notifications to all affected users
        foreach string userId in affectedUserIds {
            UserNotificationPreferences? preferences = check getUserPreferences(userId);
            if preferences is UserNotificationPreferences {
                if preferences.emailEnabled {
                    check sendEmailNotification(
                        preferences.email ?: "", 
                        template.subject, 
                        content
                    );
                }
                if preferences.pushEnabled {
                    check sendPushNotification(userId, template.subject, description);
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
            
            NotificationTemplate template = templates.get("TRIP_DELAY");
            string content = template.contentTemplate
                .replace("{tripId}", tripId)
                .replace("{routeId}", check message.routeId)
                .replace("{delayMinutes}", delayMinutes.toString())
                .replace("{newDepartureTime}", "Check app for updates");
            
            foreach string userId in affectedUserIds {
                UserNotificationPreferences? preferences = check getUserPreferences(userId);
                if preferences is UserNotificationPreferences && preferences.pushEnabled {
                    check sendPushNotification(userId, template.subject, content);
                }
            }
        }
    }
}

// Handle generic notification triggers
function handleNotificationTrigger(json message) returns error? {
    // Process custom notification triggers from other services
    log:printInfo("Processing notification trigger: " + message.toString());
}

// Helper function to send email notification
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
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection notificationsCollection = check db->getCollection("notifications");
    
    Notification notification = {
        notificationId: notificationId,
        userId: userId,
        type: notificationType,
        channel: channel,
        subject: subject,
        content: content,
        status: success ? "SENT" : "FAILED",
        sentAt: success ? time:utcToString(time:utcNow()) : (),
        createdAt: time:utcToString(time:utcNow()),
        updatedAt: time:utcToString(time:utcNow())
    };
    
    check notificationsCollection->insertOne(notification);
}

// Helper function to get user preferences
function getUserPreferences(string userId) returns UserNotificationPreferences?|error {
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection usersCollection = check db->getCollection("users");
    
    map<json> query = {"id": userId};
    stream<map<json>, error?> users = check usersCollection->find(query);
    
    map<json>|error? user = users.next();
    if user is map<json> {
        return {
            userId: userId,
            emailEnabled: check user["notifications"]["email"].ensureType(boolean),
            smsEnabled: check user["notifications"]["sms"].ensureType(boolean),
            pushEnabled: check user["notifications"]["push"].ensureType(boolean),
            email: check user["email"].ensureType(string),
            phoneNumber: user.hasKey("phoneNumber") ? check user["phoneNumber"].ensureType(string) : ()
        };
    }
    
    return ();
}

// Helper function to get affected users for service disruption
function getAffectedUsers(json affectedRoutes) returns string[]|error {
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection ticketsCollection = check db->getCollection("tickets");
    
    // Find all active tickets for affected routes
    map<json> query = {
        "tripDetails.routeId": {"$in": affectedRoutes},
        "status": {"$in": ["PAID", "VALIDATED"]}
    };
    
    stream<map<json>, error?> tickets = check ticketsCollection->find(query);
    
    string[] userIds = [];
    map<boolean> uniqueUsers = {};
    
    check from map<json> ticket in tickets
        do {
            string userId = check ticket["userId"].ensureType(string);
            if !uniqueUsers.hasKey(userId) {
                userIds.push(userId);
                uniqueUsers[userId] = true;
            }
        };
    
    return userIds;
}

// Helper function to get users for a specific trip
function getUsersForTrip(string tripId) returns string[]|error {
    mongodb:Database db = check mongoClient->getDatabase(databaseName);
    mongodb:Collection ticketsCollection = check db->getCollection("tickets");
    
    map<json> query = {
        "tripDetails.tripId": tripId,
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