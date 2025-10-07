// Shared type definitions for the transport ticketing system

// User and Authentication Types
public type User record {|
    string id?;
    string email;
    string passwordHash;
    string firstName;
    string lastName;
    string phone;
    UserRole role;
    string createdAt;
    string updatedAt?;
|};

public enum UserRole {
    PASSENGER,
    ADMIN,
    VALIDATOR
}

// Route and Trip Types
public type Route record {|
    string id?;
    string routeNumber;
    string routeName;
    string startPoint;
    string endPoint;
    string[] stops;
    TransportType transportType;
    boolean active;
    string createdAt;
    string updatedAt?;
|};

public enum TransportType {
    BUS,
    TRAIN
}

public type Trip record {|
    string id?;
    string routeId;
    string departureTime;
    string arrivalTime;
    string date;
    int availableSeats;
    int totalSeats;
    TripStatus status;
    string createdAt;
    string updatedAt?;
|};

public enum TripStatus {
    SCHEDULED,
    IN_PROGRESS,
    COMPLETED,
    CANCELLED,
    DELAYED
}

// Ticket Types
public type Ticket record {|
    string id?;
    string userId;
    string tripId?;
    TicketType ticketType;
    TicketStatus status;
    decimal price;
    string purchaseDate;
    string validFrom;
    string validUntil;
    int ridesRemaining?;
    string validatedAt?;
    string validatedBy?;
    string createdAt;
    string updatedAt?;
|};

public enum TicketType {
    SINGLE_RIDE,
    MULTIPLE_RIDE,
    DAILY_PASS,
    WEEKLY_PASS,
    MONTHLY_PASS
}

public enum TicketStatus {
    CREATED,
    PAYMENT_PENDING,
    PAID,
    VALIDATED,
    EXPIRED,
    CANCELLED
}

// Payment Types
public type Payment record {|
    string id?;
    string ticketId;
    string userId;
    decimal amount;
    PaymentMethod paymentMethod;
    PaymentStatus status;
    string transactionId?;
    string createdAt;
    string completedAt?;
|};

public enum PaymentMethod {
    CREDIT_CARD,
    DEBIT_CARD,
    MOBILE_MONEY,
    CASH
}

public enum PaymentStatus {
    PENDING,
    PROCESSING,
    COMPLETED,
    FAILED,
    REFUNDED
}

// Notification Types
public type Notification record {|
    string id?;
    string userId;
    NotificationType notificationType;
    string title;
    string message;
    boolean read;
    string createdAt;
|};

public enum NotificationType {
    TICKET_PURCHASED,
    TICKET_VALIDATED,
    TRIP_DELAYED,
    TRIP_CANCELLED,
    SCHEDULE_UPDATE,
    PAYMENT_SUCCESS,
    PAYMENT_FAILED
}

// Kafka Event Types
public type TicketRequestEvent record {|
    string userId;
    string tripId?;
    TicketType ticketType;
    decimal price;
    string timestamp;
|};

public type PaymentProcessedEvent record {|
    string ticketId;
    string userId;
    string paymentId;
    PaymentStatus status;
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
    string updateType; // DELAY, CANCELLATION, SCHEDULE_CHANGE
    string message;
    string timestamp;
|};

public type NotificationEvent record {|
    string userId;
    NotificationType notificationType;
    string title;
    string message;
    string timestamp;
|};

// API Request/Response Types
public type LoginRequest record {|
    string email;
    string password;
|};

public type LoginResponse record {|
    string token;
    User user;
|};

public type RegisterRequest record {|
    string email;
    string password;
    string firstName;
    string lastName;
    string phone;
|};

public type TicketPurchaseRequest record {|
    string userId;
    string tripId?;
    TicketType ticketType;
    PaymentMethod paymentMethod;
|};

public type TicketValidationRequest record {|
    string ticketId;
    string validatorId;
    string tripId?;
|};

public type ErrorResponse record {|
    string message;
    string code?;
    string timestamp;
|};