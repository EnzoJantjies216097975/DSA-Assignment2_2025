import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;

// Configuration
configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;
configurable string mongoUsername = "admin";
configurable string mongoPassword = "password123";
configurable string mongoDatabase = "transport_db";
configurable string kafkaBootstrapServers = "localhost:9092";

// MongoDB client
final mongodb:Client mongoClient = check new ({
    connection: {
        serverAddress: {
            host: mongoHost,
            port: mongoPort
        },
        auth: <mongodb:ScramSha256AuthCredential>{
            username: mongoUsername,
            password: mongoPassword,
            database: "admin"
        }
    }
});

// Kafka producer
final kafka:Producer kafkaProducer = check new (kafka:DEFAULT_URL, {
    clientId: "transport-service-producer",
    acks: "all",
    retryCount: 3
});

// Types
public type Route record {|
    string id;
    string routeNumber;
    string routeName;
    string startPoint;
    string endPoint;
    string[] stops;
    string transportType;
    boolean active;
    string createdAt;
    string updatedAt?;
|};

public type Trip record {|
    string id;
    string routeId;
    string departureTime;
    string arrivalTime;
    string date;
    int availableSeats;
    int totalSeats;
    string status;
    string createdAt;
    string updatedAt?;
|};

public type CreateRouteRequest record {|
    string routeNumber;
    string routeName;
    string startPoint;
    string endPoint;
    string[] stops;
    string transportType;
|};

public type CreateTripRequest record {|
    string routeId;
    string departureTime;
    string arrivalTime;
    string date;
    int totalSeats;
|};

public type ScheduleUpdateEvent record {|
    string routeId;
    string tripId?;
    string updateType;
    string message;
    string timestamp;
|};

// Service implementation
service /transport on new http:Listener(9091) {
    
    resource function get health() returns string {
        return "Transport Service is running";
    }

    // Create a new route
    resource function post routes(CreateRouteRequest request) returns http:Created|http:BadRequest|http:InternalServerError {
        do {
            if request.routeNumber.trim() == "" || request.routeName.trim() == "" {
                return <http:BadRequest>{
                    body: {
                        message: "Route number and name are required",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection routesCollection = check db->getCollection("routes");

            string routeId = uuid:createType1AsString();
            string currentTime = time:utcToString(time:utcNow());
            
            Route newRoute = {
                id: routeId,
                routeNumber: request.routeNumber,
                routeName: request.routeName,
                startPoint: request.startPoint,
                endPoint: request.endPoint,
                stops: request.stops,
                transportType: request.transportType,
                active: true,
                createdAt: currentTime
            };

            check routesCollection->insertOne(newRoute);
            log:printInfo(string `New route created: ${request.routeNumber}`);
            
            return <http:Created>{
                body: {
                    message: "Route created successfully",
                    routeId: routeId
                }
            };

        } on fail error e {
            log:printError("Error creating route", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to create route",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get all routes
    resource function get routes() returns Route[]|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection routesCollection = check db->getCollection("routes");

            stream<Route, error?> routes = check routesCollection->find({});
            Route[] routeArray = check from Route route in routes select route;
            
            return routeArray;

        } on fail error e {
            log:printError("Error fetching routes", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to fetch routes",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get route by ID
    resource function get routes/[string routeId]() returns Route|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection routesCollection = check db->getCollection("routes");

            map<json> query = {"id": routeId};
            stream<Route, error?> routes = check routesCollection->find(query);
            Route[]|error routeArray = from Route route in routes select route;
            
            if routeArray is Route[] && routeArray.length() > 0 {
                return routeArray[0];
            } else {
                return <http:NotFound>{
                    body: {
                        message: "Route not found",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

        } on fail error e {
            log:printError("Error fetching route", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to fetch route",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Create a new trip
    resource function post trips(CreateTripRequest request) returns http:Created|http:BadRequest|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            string tripId = uuid:createType1AsString();
            string currentTime = time:utcToString(time:utcNow());
            
            Trip newTrip = {
                id: tripId,
                routeId: request.routeId,
                departureTime: request.departureTime,
                arrivalTime: request.arrivalTime,
                date: request.date,
                availableSeats: request.totalSeats,
                totalSeats: request.totalSeats,
                status: "SCHEDULED",
                createdAt: currentTime
            };

            check tripsCollection->insertOne(newTrip);
            log:printInfo(string `New trip created: ${tripId}`);
            
            return <http:Created>{
                body: {
                    message: "Trip created successfully",
                    tripId: tripId
                }
            };

        } on fail error e {
            log:printError("Error creating trip", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to create trip",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get all trips
    resource function get trips() returns Trip[]|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            stream<Trip, error?> trips = check tripsCollection->find({});
            Trip[] tripArray = check from Trip trip in trips select trip;
            
            return tripArray;

        } on fail error e {
            log:printError("Error fetching trips", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to fetch trips",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get trips by route
    resource function get routes/[string routeId]/trips() returns Trip[]|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            map<json> query = {"routeId": routeId};
            stream<Trip, error?> trips = check tripsCollection->find(query);
            Trip[] tripArray = check from Trip trip in trips select trip;
            
            return tripArray;

        } on fail error e {
            log:printError("Error fetching trips for route", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to fetch trips",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get trip by ID
    resource function get trips/[string tripId]() returns Trip|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            map<json> query = {"id": tripId};
            stream<Trip, error?> trips = check tripsCollection->find(query);
            Trip[]|error tripArray = from Trip trip in trips select trip;
            
            if tripArray is Trip[] && tripArray.length() > 0 {
                return tripArray[0];
            } else {
                return <http:NotFound>{
                    body: {
                        message: "Trip not found",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

        } on fail error e {
            log:printError("Error fetching trip", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to fetch trip",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Update trip status (for delays, cancellations)
    resource function patch trips/[string tripId]/status(record {| string status; string? reason; |} request) returns http:Ok|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            // Check if trip exists
            map<json> query = {"id": tripId};
            stream<Trip, error?> trips = check tripsCollection->find(query);
            Trip[]|error tripArray = from Trip trip in trips select trip;
            
            if tripArray is error || (tripArray is Trip[] && tripArray.length() == 0) {
                return <http:NotFound>{
                    body: {
                        message: "Trip not found",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }

            Trip existingTrip = tripArray[0];
            string currentTime = time:utcToString(time:utcNow());

            // Update trip status
            mongodb:Update update = {
                "$set": {
                    "status": request.status,
                    "updatedAt": currentTime
                }
            };

            mongodb:UpdateResult updateResult = check tripsCollection->updateOne(query, update);
            
            // Publish schedule update event to Kafka
            ScheduleUpdateEvent updateEvent = {
                routeId: existingTrip.routeId,
                tripId: tripId,
                updateType: request.status,
                message: request.reason ?: string `Trip status updated to ${request.status}`,
                timestamp: currentTime
            };

            check kafkaProducer->send({
                topic: "schedule.updates",
                value: updateEvent.toJsonString().toBytes()
            });

            log:printInfo(string `Trip ${tripId} status updated to ${request.status}`);
            
            return <http:Ok>{
                body: {
                    message: "Trip status updated successfully",
                    status: request.status
                }
            };

        } on fail error e {
            log:printError("Error updating trip status", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to update trip status",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }
}