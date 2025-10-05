// User Schema - matches MongoDB users collection
public type User record {|
    string username;
    string email;
    string password;
    string role; // PASSENGER, ADMIN, VALIDATOR
    string fullName;
    string phoneNumber?;
    decimal accountBalance;
    UserNotificationPreferences notifications?;
    string createdAt;
    string updatedAt?;
|};

public type UserNotificationPreferences record {|
    boolean email;
    boolean sms;
    boolean push;
|};

// DTO for user registration (what API receives)
public type UserRegistrationRequest record {|
    string username;
    string email;
    string password;
    string fullName;
    string phoneNumber?;
|};

// DTO for user response (what API returns - no password!)
public type UserResponse record {|
    string username;
    string email;
    string fullName;
    string role;
    decimal accountBalance;
|};