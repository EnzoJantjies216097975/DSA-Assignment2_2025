import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/kafka;
import ballerinax/mongodb;

// Configuration for MongoDB connection
configurable string mongodbUrl = "mongodb://localhost:27017";
configurable string databaseName = "transport_ticketing";

// Configuration for Kafka
configurable string kafkaBootstrapServers = "localhost:9092";

// MongoDB client for database operations
mongodb:Client mongoClient = check new (mongodbUrl);

// Kafka producer for publishing events
kafka:Producer kafkaProducer = check new ({
    bootstrapServers: kafkaBootstrapServers,
    clientId: "transport-service",
    acks: "all",
    retryCount: 3
});

// Define record types for routes and trips
type Route record {
    string id?;
    string routeId;
    string routeName;
    string transportType;
    string startPoint;
    string endPoint;
    Stop[] intermediateStops;
    boolean isActive;
    string createdAt?;
    string updatedAt?;
};

type Stop record {
    string stopId;
    string stopName;
    string arrivalTime;
    string departureTime;
};

type Trip record {
    string id?;
    string tripId;
    string routeId;
    string scheduledDepartureTime;
    string scheduledArrivalTime;
    string actualDepartureTime?;
    string actualArrivalTime?;
    string status;
    string vehicleId;
    DriverInfo driverInfo;
    int capacity;
    int occupiedSeats;
    int delayMinutes?;
    Disruption[] disruptions?;
    string createdAt?;
    string updatedAt?;
};

type DriverInfo record {
    string driverId;
    string driverName;
};

type Disruption record {
    string timestamp;
    string message;
    string severity;
};

type ServiceDisruption record {
    string disruptionId;
    string[] affectedRoutes;
    string[] affectedTrips;
    string disruptionType;
    string severity;
    string title;
    string description;
    DisruptionDuration estimatedDuration;
    string[] alternativeRoutes;
    string publishedBy;
    string publishedAt;
    boolean isActive;
};

type DisruptionDuration record {
    string startTime;
    string endTime;
};

type Schedule record {
    string routeId;
    string routeName;
    Trip[] trips;
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
service /transport on new http:Listener(8082) {
    
    // Create a new route
    resource function post routes(@http:Payload Route route) returns Route|http:BadRequest|http:InternalServerError {
        // Validate input
        if route.routeName.length() == 0 || route.startPoint.length() == 0 || route.endPoint.length() == 0 {
            return <http:BadRequest>{
                body: {"error": "Route name, start point, and end point are required"}
            };
        }
        
        // Generate route ID if not provided
        if route.routeId.length() == 0 {
            string prefix = route.transportType == "BUS" ? "BUS-" : "TRAIN-";
            route.routeId = prefix + uuid:createType1AsString().substring(0, 8).toUpperAscii();
        }
        
        // Set timestamps
        string currentTime = time:utcToString(time:utcNow());
        route.createdAt = currentTime;
        route.updatedAt = currentTime;
        route.isActive = true;
        
        // Insert route into database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection routesCollection = check db->getCollection("routes");
        
        check routesCollection->insertOne(route);
        
        // Publish route creation event to Kafka
        kafka:ProducerRecord routeCreatedEvent = {
            topic: "route.events",
            key: route.routeId.toBytes(),
            value: {
                "eventType": "ROUTE_CREATED",
                "routeId": route.routeId,
                "routeName": route.routeName,
                "transportType": route.transportType,
                "startPoint": route.startPoint,
                "endPoint": route.endPoint,
                "timestamp": currentTime
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(routeCreatedEvent);
        
        log:printInfo("Route created: " + route.routeId);
        return route;
    }
    
    // Get all routes
    resource function get routes(string? transportType = ()) returns Route[]|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection routesCollection = check db->getCollection("routes");
        
        map<json> query = {"isActive": true};
        if transportType is string {
            query["transportType"] = transportType;
        }
        
        stream<Route, error?> routesStream = check routesCollection->find(query);
        
        Route[] routes = [];
        check from Route route in routesStream
            do {
                routes.push(route);
            };
        
        return routes;
    }
    
    // Get route by ID
    resource function get routes/[string routeId]() returns Route|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection routesCollection = check db->getCollection("routes");
        
        map<json> query = {"routeId": routeId};
        stream<Route, error?> routes = check routesCollection->find(query);
        
        Route|error? route = routes.next();
        if route is Route {
            return route;
        }
        
        return <http:NotFound>{
            body: {"error": "Route not found"}
        };
    }
    
    // Update route
    resource function put routes/[string routeId](@http:Payload Route updateData) 
            returns Route|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection routesCollection = check db->getCollection("routes");
        
        map<json> filter = {"routeId": routeId};
        map<json> update = {
            "$set": {
                "routeName": updateData.routeName,
                "startPoint": updateData.startPoint,
                "endPoint": updateData.endPoint,
                "intermediateStops": updateData.intermediateStops,
                "isActive": updateData.isActive,
                "updatedAt": time:utcToString(time:utcNow())
            }
        };
        
        mongodb:UpdateResult updateResult = check routesCollection->updateOne(filter, update);
        
        if updateResult.modifiedCount > 0 {
            // Publish route update event
            kafka:ProducerRecord routeUpdatedEvent = {
                topic: "route.events",
                key: routeId.toBytes(),
                value: {
                    "eventType": "ROUTE_UPDATED",
                    "routeId": routeId,
                    "updatedFields": updateData,
                    "timestamp": time:utcToString(time:utcNow())
                }.toJsonString().toBytes()
            };
            
            check kafkaProducer->send(routeUpdatedEvent);
            
            // Fetch and return updated route
            stream<Route, error?> routes = check routesCollection->find(filter);
            Route|error? route = routes.next();
            if route is Route {
                return route;
            }
        }
        
        return <http:NotFound>{
            body: {"error": "Route not found"}
        };
    }
    
    // Create a new trip
    resource function post trips(@http:Payload Trip trip) returns Trip|http:BadRequest|http:InternalServerError {
        // Validate input
        if trip.routeId.length() == 0 || trip.vehicleId.length() == 0 {
            return <http:BadRequest>{
                body: {"error": "Route ID and Vehicle ID are required"}
            };
        }
        
        // Generate trip ID
        trip.tripId = "TRIP-" + uuid:createType1AsString().substring(0, 8).toUpperAscii();
        
        // Set initial status and timestamps
        trip.status = "SCHEDULED";
        trip.occupiedSeats = 0;
        trip.delayMinutes = 0;
        
        string currentTime = time:utcToString(time:utcNow());
        trip.createdAt = currentTime;
        trip.updatedAt = currentTime;
        
        // Insert trip into database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection tripsCollection = check db->getCollection("trips");
        
        check tripsCollection->insertOne(trip);
        
        // Publish trip creation event to Kafka
        kafka:ProducerRecord tripCreatedEvent = {
            topic: "schedule.updates",
            key: trip.tripId.toBytes(),
            value: {
                "eventType": "TRIP_CREATED",
                "tripId": trip.tripId,
                "routeId": trip.routeId,
                "scheduledDepartureTime": trip.scheduledDepartureTime,
                "scheduledArrivalTime": trip.scheduledArrivalTime,
                "vehicleId": trip.vehicleId,
                "capacity": trip.capacity,
                "timestamp": currentTime
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(tripCreatedEvent);
        
        log:printInfo("Trip created: " + trip.tripId);
        return trip;
    }
    
    // Get trips by route
    resource function get trips(string? routeId = (), string? status = (), string? date = ()) 
            returns Trip[]|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection tripsCollection = check db->getCollection("trips");
        
        map<json> query = {};
        if routeId is string {
            query["routeId"] = routeId;
        }
        if status is string {
            query["status"] = status;
        }
        if date is string {
            // Filter trips by date (assuming date format is YYYY-MM-DD)
            string startOfDay = date + "T00:00:00Z";
            string endOfDay = date + "T23:59:59Z";
            query["scheduledDepartureTime"] = {
                "$gte": startOfDay,
                "$lte": endOfDay
            };
        }
        
        stream<Trip, error?> tripsStream = check tripsCollection->find(query);
        
        Trip[] trips = [];
        check from Trip trip in tripsStream
            do {
                trips.push(trip);
            };
        
        return trips;
    }
    
    // Get trip by ID
    resource function get trips/[string tripId]() returns Trip|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection tripsCollection = check db->getCollection("trips");
        
        map<json> query = {"tripId": tripId};
        stream<Trip, error?> trips = check tripsCollection->find(query);
        
        Trip|error? trip = trips.next();
        if trip is Trip {
            return trip;
        }
        
        return <http:NotFound>{
            body: {"error": "Trip not found"}
        };
    }
    
    // Update trip status
    resource function put trips/[string tripId]/status(@http:Payload map<json> statusUpdate) 
            returns Trip|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection tripsCollection = check db->getCollection("trips");
        
        string newStatus = check statusUpdate["status"].ensureType();
        string currentTime = time:utcToString(time:utcNow());
        
        map<json> filter = {"tripId": tripId};
        map<json> update = {
            "$set": {
                "status": newStatus,
                "updatedAt": currentTime
            }
        };
        
        // Add actual departure/arrival times based on status
        if newStatus == "IN_PROGRESS" {
            update["$set"]["actualDepartureTime"] = currentTime;
        } else if newStatus == "COMPLETED" {
            update["$set"]["actualArrivalTime"] = currentTime;
        }
        
        // Handle delay information
        if statusUpdate.hasKey("delayMinutes") {
            int delayMinutes = check statusUpdate["delayMinutes"].ensureType();
            update["$set"]["delayMinutes"] = delayMinutes;
        }
        
        mongodb:UpdateResult updateResult = check tripsCollection->updateOne(filter, update);
        
        if updateResult.modifiedCount > 0 {
            // Fetch updated trip
            stream<Trip, error?> trips = check tripsCollection->find(filter);
            Trip|error? trip = trips.next();
            
            if trip is Trip {
                // Publish trip status update event
                kafka:ProducerRecord statusUpdateEvent = {
                    topic: "schedule.updates",
                    key: tripId.toBytes(),
                    value: {
                        "eventType": "TRIP_STATUS_UPDATED",
                        "tripId": tripId,
                        "routeId": trip.routeId,
                        "oldStatus": statusUpdate["oldStatus"],
                        "newStatus": newStatus,
                        "delayMinutes": trip.delayMinutes,
                        "timestamp": currentTime
                    }.toJsonString().toBytes()
                };
                
                check kafkaProducer->send(statusUpdateEvent);
                
                log:printInfo("Trip status updated: " + tripId + " -> " + newStatus);
                return trip;
            }
        }
        
        return <http:NotFound>{
            body: {"error": "Trip not found"}
        };
    }
    
    // Publish service disruption
    resource function post disruptions(@http:Payload ServiceDisruption disruption) 
            returns ServiceDisruption|http:BadRequest|http:InternalServerError {
        // Validate input
        if disruption.title.length() == 0 || disruption.description.length() == 0 {
            return <http:BadRequest>{
                body: {"error": "Title and description are required"}
            };
        }
        
        // Generate disruption ID
        disruption.disruptionId = "DISRUPT-" + uuid:createType1AsString().substring(0, 8).toUpperAscii();
        disruption.publishedAt = time:utcToString(time:utcNow());
        disruption.isActive = true;
        
        // Insert disruption into database
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection disruptionsCollection = check db->getCollection("serviceDisruptions");
        
        check disruptionsCollection->insertOne(disruption);
        
        // Publish disruption event to Kafka
        kafka:ProducerRecord disruptionEvent = {
            topic: "schedule.updates",
            key: disruption.disruptionId.toBytes(),
            value: {
                "eventType": "SERVICE_DISRUPTION",
                "disruptionId": disruption.disruptionId,
                "affectedRoutes": disruption.affectedRoutes,
                "affectedTrips": disruption.affectedTrips,
                "disruptionType": disruption.disruptionType,
                "severity": disruption.severity,
                "title": disruption.title,
                "description": disruption.description,
                "estimatedDuration": disruption.estimatedDuration,
                "alternativeRoutes": disruption.alternativeRoutes,
                "timestamp": disruption.publishedAt
            }.toJsonString().toBytes()
        };
        
        check kafkaProducer->send(disruptionEvent);
        
        log:printInfo("Service disruption published: " + disruption.disruptionId);
        return disruption;
    }
    
    // Get active disruptions
    resource function get disruptions(string? routeId = (), string? severity = ()) 
            returns ServiceDisruption[]|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection disruptionsCollection = check db->getCollection("serviceDisruptions");
        
        map<json> query = {"isActive": true};
        if routeId is string {
            query["affectedRoutes"] = {"$in": [routeId]};
        }
        if severity is string {
            query["severity"] = severity;
        }
        
        stream<ServiceDisruption, error?> disruptionsStream = check disruptionsCollection->find(query);
        
        ServiceDisruption[] disruptions = [];
        check from ServiceDisruption disruption in disruptionsStream
            do {
                disruptions.push(disruption);
            };
        
        return disruptions;
    }
    
    // Get schedule for a specific date
    resource function get schedule(string date, string? transportType = ()) 
            returns Schedule[]|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection tripsCollection = check db->getCollection("trips");
        mongodb:Collection routesCollection = check db->getCollection("routes");
        
        // First, get relevant routes
        map<json> routeQuery = {"isActive": true};
        if transportType is string {
            routeQuery["transportType"] = transportType;
        }
        
        stream<Route, error?> routesStream = check routesCollection->find(routeQuery);
        Route[] routes = [];
        check from Route route in routesStream
            do {
                routes.push(route);
            };
        
        // For each route, get trips for the specified date
        Schedule[] schedules = [];
        foreach Route route in routes {
            string startOfDay = date + "T00:00:00Z";
            string endOfDay = date + "T23:59:59Z";
            
            map<json> tripQuery = {
                "routeId": route.routeId,
                "scheduledDepartureTime": {
                    "$gte": startOfDay,
                    "$lte": endOfDay
                }
            };
            
            stream<Trip, error?> tripsStream = check tripsCollection->find(tripQuery);
            Trip[] trips = [];
            check from Trip trip in tripsStream
                do {
                    trips.push(trip);
                };
            
            if trips.length() > 0 {
                schedules.push({
                    routeId: route.routeId,
                    routeName: route.routeName,
                    trips: trips
                });
            }
        }
        
        return schedules;
    }
    
    // Update seat occupancy for a trip
    resource function put trips/[string tripId]/occupancy(@http:Payload map<json> occupancyUpdate) 
            returns map<json>|http:NotFound|http:InternalServerError {
        mongodb:Database db = check mongoClient->getDatabase(databaseName);
        mongodb:Collection tripsCollection = check db->getCollection("trips");
        
        int seatsToAdd = check occupancyUpdate["seatsToAdd"].ensureType();
        
        // First, fetch the trip to check capacity
        map<json> query = {"tripId": tripId};
        stream<Trip, error?> trips = check tripsCollection->find(query);
        Trip|error? trip = trips.next();
        
        if trip is Trip {
            int newOccupancy = trip.occupiedSeats + seatsToAdd;
            
            // Check if capacity is exceeded
            if newOccupancy > trip.capacity {
                return <http:BadRequest>{
                    body: {
                        "error": "Not enough seats available",
                        "availableSeats": trip.capacity - trip.occupiedSeats
                    }
                };
            }
            
            // Update occupancy
            map<json> update = {
                "$set": {
                    "occupiedSeats": newOccupancy,
                    "updatedAt": time:utcToString(time:utcNow())
                }
            };
            
            mongodb:UpdateResult updateResult = check tripsCollection->updateOne(query, update);
            
            return {
                "tripId": tripId,
                "newOccupancy": newOccupancy,
                "capacity": trip.capacity,
                "availableSeats": trip.capacity - newOccupancy
            };
        }
        
        return <http:NotFound>{
            body: {"error": "Trip not found"}
        };
    }
}