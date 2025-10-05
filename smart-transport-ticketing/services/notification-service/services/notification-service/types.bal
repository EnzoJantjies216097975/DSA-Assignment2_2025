// Notification Schema
public type Notification record {|
    string notificationId;
    string userId;
    NotificationType notificationType;
    string title;
    string message;
    Priority priority;
    boolean isRead;
    string? readAt;
    string? relatedEntityId;
    string? relatedEntityType;
    json? metadata;
    NotificationChannel[] channels?;
    DeliveryStatus? deliveryStatus;
    string createdAt;
    string updatedAt?;
|};

public enum NotificationType {
    TICKET_VALIDATED,
    SCHEDULE_UPDATE,
    PAYMENT_CONFIRMATION,
    SERVICE_DISRUPTION,
    TRIP_REMINDER,
    ACCOUNT_UPDATE
}

public enum Priority {
    LOW,
    MEDIUM,
    HIGH,
    URGENT
}

public enum NotificationChannel {
    EMAIL,
    SMS,
    PUSH,
    IN_APP
}

public type DeliveryStatus record {|
    string? email;
    string? sms;
    string? push;
|};