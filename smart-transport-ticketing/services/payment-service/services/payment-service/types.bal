// Payment Schema
public type Payment record {|
    string paymentId;
    string userId;
    string ticketId;
    decimal amount;
    PaymentMethod paymentMethod;
    PaymentStatus status;
    string? transactionReference;
    string? paymentGateway;
    string? failureReason;
    string paymentDate;
    string createdAt;
    string updatedAt?;
|};

public enum PaymentMethod {
    BALANCE,
    CARD,
    MOBILE_MONEY,
    CASH
}

public enum PaymentStatus {
    PENDING,
    SUCCESS,
    FAILED,
    REFUNDED
}