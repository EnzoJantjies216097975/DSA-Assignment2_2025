// Ticket Schema - matches MongoDB tickets collection
public type Ticket record {|
    string ticketId;
    string userId;
    string routeId;
    string? tripId;
    TicketType ticketType;
    TicketStatus status;
    decimal price;
    int ridesRemaining;
    string validFrom;
    string validUntil;
    string purchaseDate;
    string? qrCode;
    ValidationRecord[] validationHistory?;
    string createdAt;
    string updatedAt?;
|};

public enum TicketType {
    SINGLE_RIDE,
    MULTI_RIDE,
    DAY_PASS,
    WEEKLY_PASS,
    MONTHLY_PASS
}

public enum TicketStatus {
    CREATED,
    PENDING_PAYMENT,
    PAID,
    VALIDATED,
    EXPIRED,
    CANCELLED
}

public type ValidationRecord record {|
    string validatedAt;
    string validatorId;
    string tripId;
    string location;
|};

// DTO for ticket purchase request
public type TicketPurchaseRequest record {|
    string userId;
    string routeId;
    string? tripId;
    TicketType ticketType;
    int quantity;
|};