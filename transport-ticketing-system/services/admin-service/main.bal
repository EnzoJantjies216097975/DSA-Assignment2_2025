import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/mongodb;

// Configuration
configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;
configurable string mongoUsername = "admin";
configurable string mongoPassword = "password123";
configurable string mongoDatabase = "transport_db";
configurable string transportServiceUrl = "http://localhost:9091";

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

// HTTP client for Transport Service
final http:Client transportClient = check new (transportServiceUrl);

// Types
public type TicketSalesReport record {|
    int totalTicketsSold;
    decimal totalRevenue;
    map<int> ticketsByType;
    map<decimal> revenueByType;
    string reportDate;
|};

public type PassengerTrafficReport record {|
    int totalPassengers;
    map<int> passengersByRoute;
    string reportDate;
|};

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

public type Ticket record {|
    string id;
    string userId;
    string tripId?;
    string ticketType;
    string status;
    decimal price;
    string purchaseDate;
    string validFrom;
    string validUntil;
    int ridesRemaining?;
    string validatedAt?;
    string validatedBy?;
    string paymentId?;
    string createdAt;
    string updatedAt?;
|};

// Service implementation
service /admin on new http:Listener(9095) {
    
    resource function get health() returns string {
        return "Admin Service is running";
    }

    // Get ticket sales report
    resource function get reports/sales() returns TicketSalesReport|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");

            // Fetch all paid tickets
            map<json> query = {"status": "PAID"};
            stream<Ticket, error?> tickets = check ticketsCollection->find(query);
            Ticket[] ticketArray = check from Ticket ticket in tickets select ticket;
            
            int totalTickets = ticketArray.length();
            decimal totalRevenue = 0.0;
            map<int> ticketsByType = {};
            map<decimal> revenueByType = {};
            
            foreach Ticket ticket in ticketArray {
                totalRevenue += ticket.price;
                
                // Count by type
                if ticketsByType.hasKey(ticket.ticketType) {
                    ticketsByType[ticket.ticketType] = ticketsByType.get(ticket.ticketType) + 1;
                } else {
                    ticketsByType[ticket.ticketType] = 1;
                }
                
                // Revenue by type
                if revenueByType.hasKey(ticket.ticketType) {
                    revenueByType[ticket.ticketType] = revenueByType.get(ticket.ticketType) + ticket.price;
                } else {
                    revenueByType[ticket.ticketType] = ticket.price;
                }
            }
            
            return {
                totalTicketsSold: totalTickets,
                totalRevenue: totalRevenue,
                ticketsByType: ticketsByType,
                revenueByType: revenueByType,
                reportDate: time:utcToString(time:utcNow())
            };

        } on fail error e {
            log:printError("Error generating sales report", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to generate sales report",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get passenger traffic report
    resource function get reports/traffic() returns PassengerTrafficReport|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");
            mongodb:Collection tripsCollection = check db->getCollection("trips");

            // Fetch all validated tickets
            map<json> query = {"status": "VALIDATED"};
            stream<Ticket, error?> tickets = check ticketsCollection->find(query);
            Ticket[] ticketArray = check from Ticket ticket in tickets select ticket;
            
            int totalPassengers = ticketArray.length();
            map<int> passengersByRoute = {};
            
            foreach Ticket ticket in ticketArray {
                if ticket.tripId is string {
                    // Get trip to find route
                    map<json> tripQuery = {"id": ticket.tripId};
                    stream<Trip, error?> trips = check tripsCollection->find(tripQuery);
                    Trip[]|error tripArray = from Trip trip in trips select trip;
                    
                    if tripArray is Trip[] && tripArray.length() > 0 {
                        string routeId = tripArray[0].routeId;
                        if passengersByRoute.hasKey(routeId) {
                            passengersByRoute[routeId] = passengersByRoute.get(routeId) + 1;
                        } else {
                            passengersByRoute[routeId] = 1;
                        }
                    }
                }
            }
            
            return {
                totalPassengers: totalPassengers,
                passengersByRoute: passengersByRoute,
                reportDate: time:utcToString(time:utcNow())
            };

        } on fail error e {
            log:printError("Error generating traffic report", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to generate traffic report",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }

    // Get all routes (proxy to transport service)
    resource function get routes() returns Route[]|http:InternalServerError {
        do {
            Route[] routes = check transportClient->/routes.get();
            return routes;
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

    // Get all trips (proxy to transport service)
    resource function get trips() returns Trip[]|http:InternalServerError {
        do {
            Trip[] trips = check transportClient->/trips.get();
            return trips;
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

    // Update trip status (for delays/cancellations)
    resource function patch trips/[string tripId]/status(record {| string status; string? reason; |} request) returns http:Ok|http:InternalServerError {
        do {
            http:Response response = check transportClient->/trips/[tripId]/status.patch(request);
            
            if response.statusCode == 200 {
                return <http:Ok>{
                    body: {
                        message: "Trip status updated successfully",
                        tripId: tripId,
                        status: request.status
                    }
                };
            } else {
                return <http:InternalServerError>{
                    body: {
                        message: "Failed to update trip status",
                        timestamp: time:utcToString(time:utcNow())
                    }
                };
            }
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

    // Dashboard summary
    resource function get dashboard() returns record {| int totalRoutes; int totalTrips; int totalTickets; decimal totalRevenue; |}|http:InternalServerError {
        do {
            mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
            mongodb:Collection routesCollection = check db->getCollection("routes");
            mongodb:Collection tripsCollection = check db->getCollection("trips");
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");

            // Count routes
            stream<Route, error?> routes = check routesCollection->find({});
            Route[] routeArray = check from Route route in routes select route;
            
            // Count trips
            stream<Trip, error?> trips = check tripsCollection->find({});
            Trip[] tripArray = check from Trip trip in trips select trip;
            
            // Count tickets and calculate revenue
            map<json> paidQuery = {"status": "PAID"};
            stream<Ticket, error?> tickets = check ticketsCollection->find(paidQuery);
            Ticket[] ticketArray = check from Ticket ticket in tickets select ticket;
            
            decimal totalRevenue = 0.0;
            foreach Ticket ticket in ticketArray {
                totalRevenue += ticket.price;
            }
            
            return {
                totalRoutes: routeArray.length(),
                totalTrips: tripArray.length(),
                totalTickets: ticketArray.length(),
                totalRevenue: totalRevenue
            };

        } on fail error e {
            log:printError("Error fetching dashboard data", 'error = e);
            return <http:InternalServerError>{
                body: {
                    message: "Failed to fetch dashboard data",
                    timestamp: time:utcToString(time:utcNow())
                }
            };
        }
    }
}