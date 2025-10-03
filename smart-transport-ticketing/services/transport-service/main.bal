import ballerina/io;
import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;

configurable string mongoHost = "mongodb";
configurable int mongoPort = 27017;
configurable string dbName = "transport_ticketing";
configurable string kafkaBootstrapServers = "kafka:9092";

mongodb:Client mongoClient = check new ({
    connection: {
        host: mongoHost,
        port: mongoPort,
        auth: {
            username: "",
            password: ""
        },
        options: {
            sslEnabled: false,
            serverSelectionTimeout: 5000
        }
    }
});

// Kafka producer for publishing events
kafka:Producer kafkaProducer = check new ({
    bootstrapServers: kafkaBootstrapServers,
    clientId: "transport-service-producer",
    acks: "all",
    compressionType: "snappy",
    retryCount: 3
});

// Route represents a bus or train line
type Route record {
    string routeId;
    string name;
    string routeType;  // "BUS" or "TRAIN"
    Stop[] stops;
    boolean active;
    time:Utc? createdAt;
};

// Stop represents a station or bus stop
type Stop record {
    string stopId;
    string name;
    int stopOrder;  // Order in which stops are visited
};

// Trip represents a scheduled departure
type Trip record {
    string tripId;
    string routeId;
    string departureTime;  // Format: "HH:MM"
    string arrivalTime;    // Format: "HH:MM"
    string[] days;         // Days of week this trip runs
    int capacity;          // Maximum passengers
    int currentOccupancy;  // Current passenger count
    time:Utc? createdAt;
};

// ServiceDisruption represents delays or cancellations
type ServiceDisruption record {
    string disruptionId;
    string routeId;
    string disruptionType;  // "DELAY", "CANCELLATION", "ROUTE_CHANGE"
    string description;
    time:Utc startTime;
    time:Utc? endTime;
    boolean active;
};

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE"],
        allowHeaders: ["Content-Type", "Authorization"]
    }
}
service /transport on new http:Listener(8081) {
    
    // Health check endpoint
    resource function get health() returns http:Response {
        http:Response response = new;
        response.statusCode = 200;
        response.setJsonPayload({
            status: "healthy",
            service: "transport-service",
            timestamp: time:utcNow().toString()
        });
        return response;
    }
    
    // Create a new route (admin operation)
    resource function post routes(@http:Payload Route route) 
            returns http:Response|error {
        
        log:printInfo("Creating new route: " + route.name);
        
        // Generate unique route ID
        route.routeId = "ROUTE_" + time:utcNow()[0].toString();
        route.createdAt = time:utcNow();
        
        // Validate route data
        if (route.stops.length() < 2) {
            http:Response response = new;
            response.statusCode = 400;
            response.setJsonPayload({
                error: "A route must have at least 2 stops"
            });
            return response;
        }
        
        // Validate route type
        if (route.routeType != "BUS" && route.routeType != "TRAIN") {
            http:Response response = new;
            response.statusCode = 400;
            response.setJsonPayload({
                error: "Route type must be either BUS or TRAIN"
            });
            return response;
        }
        
        // Store in MongoDB
        mongodb:Database db = check mongoClient->getDatabase(dbName);
        mongodb:Collection routes = check db->getCollection("routes");
        
        mongodb:Error? insertResult = routes->insertOne(route);
        if (insertResult is mongodb:Error) {
            log:printError("Failed to create route", 'error = insertResult);
            http:Response response = new;
            response.statusCode = 500;
            response.setJsonPayload({error: "Failed to create route"});
            return response;
        }
        
        // Publish route creation event
        // Other services can react to new routes being added
        kafka:Error? sendResult = kafkaProducer->send({
            topic: "schedule.updates",
            value: {
                type: "ROUTE_CREATED",
                routeId: route.routeId,
                name: route.name,
                routeType: route.routeType,
                stopCount: route.stops.length(),
                timestamp: time:utcNow().toString()
            }.toString()
        });
        
        if (sendResult is kafka:Error) {
            log:printWarn("Failed to publish route creation event", 'error = sendResult);
        }
        
        http:Response response = new;
        response.statusCode = 201;
        response.setJsonPayload({
            message: "Route created successfully",
            routeId: route.routeId
        });
        return response;
    }
    
    // Get all active routes
    resource function get routes(string? routeType = ()) 
            returns http:Response|error {
        
        log:printInfo("Fetching routes" + 
                     (routeType is string ? " of type: " + routeType : ""));
        
        mongodb:Database db = check mongoClient->getDatabase(dbName);
        mongodb:Collection routes = check db->getCollection("routes");
        
        // Build query based on parameters
        json query = {active: true};
        if (routeType is string) {
            query = {active: true, routeType: routeType};
        }
        
        stream<Route, mongodb:Error?> routeStream = check routes->find(query);
        Route[] routeList = check from Route route in routeStream select route;
        
        http:Response response = new;
        response.statusCode = 200;
        response.setJsonPayload({
            count: routeList.length(),
            routes: routeList
        });
        return response;
    }
    
    // Create a new trip on a route
    resource function post trips(@http:Payload Trip trip) 
            returns http:Response|error {
        
        log:printInfo("Creating new trip for route: " + trip.routeId);
        
        // First, verify the route exists
        mongodb:Database db = check mongoClient->getDatabase(dbName);
        mongodb:Collection routes = check db->getCollection("routes");
        
        stream<Route, mongodb:Error?> routeStream = 
            check routes->find({routeId: trip.routeId});
        Route[] routeList = check from Route route in routeStream select route;
        
        if (routeList.length() == 0) {
            http:Response response = new;
            response.statusCode = 404;
            response.setJsonPayload({error: "Route not found"});
            return response;
        }
        
        // Generate trip ID and initialize fields
        trip.tripId = "TRIP_" + time:utcNow()[0].toString();
        trip.currentOccupancy = 0;
        trip.createdAt = time:utcNow();
        
        // Validate days array
        string[] validDays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
        foreach string day in trip.days {
            if (validDays.indexOf(day) is ()) {
                http:Response response = new;
                response.statusCode = 400;
                response.setJsonPayload({
                    error: "Invalid day: " + day + 
                           ". Must be one of: MON, TUE, WED, THU, FRI, SAT, SUN"
                });
                return response;
            }
        }
        
        // Store trip
        mongodb:Collection trips = check db->getCollection("trips");
        mongodb:Error? insertResult = trips->insertOne(trip);
        
        if (insertResult is mongodb:Error) {
            log:printError("Failed to create trip", 'error = insertResult);
            http:Response response = new;
            response.statusCode = 500;
            response.setJsonPayload({error: "Failed to create trip"});
            return response;
        }
        
        // Publish trip creation event
        kafka:Error? sendResult = kafkaProducer->send({
            topic: "schedule.updates",
            value: {
                type: "TRIP_CREATED",
                tripId: trip.tripId,
                routeId: trip.routeId,
                departureTime: trip.departureTime,
                days: trip.days,
                capacity: trip.capacity,
                timestamp: time:utcNow().toString()
            }.toString()
        });
        
        http:Response response = new;
        response.statusCode = 201;
        response.setJsonPayload({
            message: "Trip created successfully",
            tripId: trip.tripId
        });
        return response;
    }
    
    // Report a service disruption
    resource function post disruptions(@http:Payload ServiceDisruption disruption) 
            returns http:Response|error {
        
        log:printInfo("Reporting disruption for route: " + disruption.routeId);
        
        // Generate disruption ID
        disruption.disruptionId = "DISRUPTION_" + time:utcNow()[0].toString();
        disruption.startTime = time:utcNow();
        disruption.active = true;
        
        // Validate disruption type
        string[] validTypes = ["DELAY", "CANCELLATION", "ROUTE_CHANGE"];
        if (validTypes.indexOf(disruption.disruptionType) is ()) {
            http:Response response = new;
            response.statusCode = 400;
            response.setJsonPayload({
                error: "Invalid disruption type. Must be: DELAY, CANCELLATION, or ROUTE_CHANGE"
            });
            return response;
        }
        
        // Store disruption
        mongodb:Database db = check mongoClient->getDatabase(dbName);
        mongodb:Collection disruptions = check db->getCollection("service_disruptions");
        
        mongodb:Error? insertResult = disruptions->insertOne(disruption);
        if (insertResult is mongodb:Error) {
            log:printError("Failed to create disruption", 'error = insertResult);
            http:Response response = new;
            response.statusCode = 500;
            response.setJsonPayload({error: "Failed to report disruption"});
            return response;
        }
        
        // Publish disruption event - critical for notifying passengers
        kafka:Error? sendResult = kafkaProducer->send({
            topic: "service.disruptions",
            value: {
                type: "DISRUPTION_REPORTED",
                disruptionId: disruption.disruptionId,
                routeId: disruption.routeId,
                disruptionType: disruption.disruptionType,
                description: disruption.description,
                timestamp: time:utcNow().toString()
            }.toString(),
            partition: 0  // Use partition 0 for all disruptions to maintain order
        });
        
        if (sendResult is kafka:Error) {
            log:printError("Failed to publish disruption event", 'error = sendResult);
        }
        
        http:Response response = new;
        response.statusCode = 201;
        response.setJsonPayload({
            message: "Disruption reported successfully",
            disruptionId: disruption.disruptionId
        });
        return response;
    }
}