// Route Schema
public type Route record {|
    string routeId;
    string routeName;
    TransportType transportType;
    string startPoint;
    string endPoint;
    IntermediateStop[] intermediateStops?;
    decimal fare;
    float? distance;
    int? estimatedDuration;
    boolean isActive;
    string createdAt;
    string updatedAt?;
|};

public enum TransportType {
    BUS,
    TRAIN
}

public type IntermediateStop record {|
    string stopId;
    string stopName;
    string? arrivalTime;
    string? departureTime;
|};

// Trip Schema
public type Trip record {|
    string tripId;
    string routeId;
    string departureTime;
    string arrivalTime;
    TripStatus status;
    string? vehicleId;
    string? driverId;
    int availableSeats;
    int totalSeats;
    Location? currentLocation;
    DelayInfo? delayInfo;
    string createdAt;
    string updatedAt?;
|};

public enum TripStatus {
    SCHEDULED,
    DELAYED,
    CANCELLED,
    IN_PROGRESS,
    COMPLETED
}

public type Location record {|
    float latitude;
    float longitude;
    string lastUpdated;
|};

public type DelayInfo record {|
    int delayMinutes;
    string reason;
|};