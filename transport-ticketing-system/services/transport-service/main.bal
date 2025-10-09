import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;

// Configuration
configurable string mongoHost = ?;
configurable int mongoPort = ?;
configurable string mongoUsername = ?;
configurable string mongoPassword = ?;
configurable string mongoDatabase = ?;
configurable string kafkaBootstrapServers = ?;

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

// Types - Made more flexible to handle MongoDB data
public type Route record {
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
};

public type Trip record {
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
};

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
                http:BadRequest badRequest = {
                    body: {
                        message: "Route number and name are required",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
                return badRequest;
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
            
            http:Created created = {
                body: {
                    message: "Route created successfully",
                    routeId: routeId
                }
            };
            return created;

        } on fail error e {
            log:printError("Error creating route", 'error = e, stackTrace = e.stackTrace());
            http:InternalServerError internalError = {
                body: {
                    message: string `Failed to create route: ${e.message()}`,
                    timestamp: time:utcToString(time:utcNow())
                }
            };
            return internalError;
        }
    }

    // Get all routes - FIXED VERSION
    resource function get routes() returns json[]|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection routesCollection = check db->getCollection("routes");

            // Use projection to exclude _id field
            map<json> projection = {"_id": 0};
            stream<map<json>, error?> routeStream = check routesCollection->find({}, projection = projection);
            
            json[] routes = [];
            error? e = routeStream.forEach(function(map<json> route) {
                routes.push(route);
            });
            
            if e is error {
                log:printError("Error processing routes", 'error = e);
                http:InternalServerError internalError = {
                    body: {
                        message: "Failed to process routes",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
                return internalError;
            }
            
            log:printInfo(string `Fetched ${routes.length()} routes`);
            return routes;

        } on fail error e {
            log:printError("Error fetching routes", 'error = e, stackTrace = e.stackTrace());
            http:InternalServerError internalError = {
                body: {
                    message: string `Failed to fetch routes: ${e.message()}`,
                    timestamp: time:utcToString(time:utcNow())
                }
            };
            return internalError;
        }
    }

    // Get route by ID
    resource function get routes/[string routeId]() returns json|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection routesCollection = check db->getCollection("routes");

            map<json> query = {"id": routeId};
            map<json> projection = {"_id": 0};
            stream<map<json>, error?> routes = check routesCollection->find(query, projection = projection);
            
            map<json>[] routeArray = [];
            error? e = routes.forEach(function(map<json> route) {
                routeArray.push(route);
            });
            
            if e is error {
                log:printError("Error processing route", 'error = e);
                http:InternalServerError internalError = {
                    body: {
                        message: "Failed to process route",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
                return internalError;
            }
            
            if routeArray.length() > 0 {
                return routeArray[0];
            } else {
                http:NotFound notFound = {
                    body: {
                        message: "Route not found",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
                return notFound;
            }

        } on fail error e {
            log:printError("Error fetching route", 'error = e, stackTrace = e.stackTrace());
            http:InternalServerError internalError = {
                body: {
                    message: string `Failed to fetch route: ${e.message()}`,
                    timestamp: time:utcToString(time:utcNow())
                }
            };
            return internalError;
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
            
            http:Created created = {
                body: {
                    message: "Trip created successfully",
                    tripId: tripId
                }
            };
            return created;

        } on fail error e {
            log:printError("Error creating trip", 'error = e, stackTrace = e.stackTrace());
            http:InternalServerError internalError = {
                body: {
                    message: string `Failed to create trip: ${e.message()}`,
                    timestamp: time:utcToString(time:utcNow())
                }
            };
            return internalError;
        }
    }

    // Get all trips 
    resource function get trips() returns json[]|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            map<json> projection = {"_id": 0};
            stream<map<json>, error?> tripStream = check tripsCollection->find({}, projection = projection);
            
            json[] trips = [];
            error? e = tripStream.forEach(function(map<json> trip) {
                trips.push(trip);
            });
            
            if e is error {
                log:printError("Error processing trips", 'error = e);
                http:InternalServerError internalError = {
                    body: {
                        message: "Failed to process trips",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
                return internalError;
            }
            
            log:printInfo(string `Fetched ${trips.length()} trips`);
            return trips;

        } on fail error e {
            log:printError("Error fetching trips", 'error = e, stackTrace = e.stackTrace());
            http:InternalServerError internalError = {
                body: {
                    message: string `Failed to fetch trips: ${e.message()}`,
                    timestamp: time:utcToString(time:utcNow())
                }
            };
            return internalError;
        }
    }

    // Get trips by route
    resource function get routes/[string routeId]/trips() returns json[]|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            map<json> query = {"routeId": routeId};
            map<json> projection = {"_id": 0};
            stream<map<json>, error?> tripStream = check tripsCollection->find(query, projection = projection);
            
            json[] trips = [];
            error? e = tripStream.forEach(function(map<json> trip) {
                trips.push(trip);
            });
            
            if e is error {
                log:printError("Error processing trips for route", 'error = e);
                http:InternalServerError internalError = {
                    body: {
                        message: "Failed to process trips",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
                return internalError;
            }
            
            return trips;

        } on fail error e {
            log:printError("Error fetching trips for route", 'error = e, stackTrace = e.stackTrace());
            http:InternalServerError internalError = {
                body: {
                    message: string `Failed to fetch trips: ${e.message()}`,
                    timestamp: time:utcToString(time:utcNow())
                }
            };
            return internalError;
        }
    }

    // Get trip by ID
    resource function get trips/[string tripId]() returns json|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            map<json> query = {"id": tripId};
            map<json> projection = {"_id": 0};
            stream<map<json>, error?> trips = check tripsCollection->find(query, projection = projection);
            
            map<json>[] tripArray = [];
            error? e = trips.forEach(function(map<json> trip) {
                tripArray.push(trip);
            });
            
            if e is error {
                log:printError("Error processing trip", 'error = e);
                http:InternalServerError internalError = {
                    body: {
                        message: "Failed to process trip",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
                return internalError;
            }
            
            if tripArray.length() > 0 {
                return tripArray[0];
            } else {
                http:NotFound notFound = {
                    body: {
                        message: "Trip not found",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
                return notFound;
            }

        } on fail error e {
            log:printError("Error fetching trip", 'error = e, stackTrace = e.stackTrace());
            http:InternalServerError internalError = {
                body: {
                    message: string `Failed to fetch trip: ${e.message()}`,
                    timestamp: time:utcToString(time:utcNow())
                }
            };
            return internalError;
        }
    }

    // Update trip status (for delays, cancellations)
    resource function patch trips/[string tripId]/status(record {| string status; string? reason; |} request) returns http:Ok|http:NotFound|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            // Check if trip exists
            map<json> query = {"id": tripId};
            map<json> projection = {"_id": 0};
            stream<map<json>, error?> trips = check tripsCollection->find(query, projection = projection);
            
            map<json>[] tripArray = [];
            error? e = trips.forEach(function(map<json> trip) {
                tripArray.push(trip);
            });
            
            if e is error || tripArray.length() == 0 {
                http:NotFound notFound = {
                    body: {
                        message: "Trip not found",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
                return notFound;
            }

            map<json> existingTrip = tripArray[0];
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
            string routeId = existingTrip["routeId"].toString();
            ScheduleUpdateEvent updateEvent = {
                routeId: routeId,
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
            
            http:Ok ok = {
                body: {
                    message: "Trip status updated successfully",
                    status: request.status
                }
            };
            return ok;

        } on fail error e {
            log:printError("Error updating trip status", 'error = e, stackTrace = e.stackTrace());
            http:InternalServerError internalError = {
                body: {
                    message: string `Failed to update trip status: ${e.message()}`,
                    timestamp: time:utcToString(time:utcNow())
                }
            };
            return internalError;
        }
    }
}