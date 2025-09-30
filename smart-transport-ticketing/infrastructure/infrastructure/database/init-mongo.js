db = db.getSiblingDB('transport_ticketing');

// Create Users Collection
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "username", "email", "password", "role", "fullName", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        username: { bsonType: "string" },
        email: { bsonType: "string" },
        password: { bsonType: "string" },
        role: { bsonType: "string", enum: ["PASSENGER", "ADMIN", "VALIDATOR"] },
        fullName: { bsonType: "string" },
        phoneNumber: { bsonType: "string" },
        accountBalance: { bsonType: "decimal" },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// Create Routes Collection
db.createCollection("routes", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "routeId", "routeName", "transportType", "startPoint", "endPoint", "isActive"],
      properties: {
        _id: { bsonType: "objectId" },
        routeId: { bsonType: "string" },
        routeName: { bsonType: "string" },
        transportType: { bsonType: "string", enum: ["BUS", "TRAIN"] },
        startPoint: { bsonType: "string" },
        endPoint: { bsonType: "string" },
        intermediateStops: {
          bsonType: "array",
          items: {
            bsonType: "object",
            properties: {
              stopId: { bsonType: "string" },
              stopName: { bsonType: "string" },
              sequence: { bsonType: "int" }
            }
          }
        },
        isActive: { bsonType: "bool" },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// Create Tickets Collection
db.createCollection("tickets", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "ticketId", "userId", "ticketType", "status", "price"],
      properties: {
        _id: { bsonType: "objectId" },
        ticketId: { bsonType: "string" },
        userId: { bsonType: "string" },
        ticketType: { 
          bsonType: "string", 
          enum: ["SINGLE", "RETURN", "DAY_PASS", "WEEK_PASS", "MONTH_PASS"] 
        },
        status: { 
          bsonType: "string", 
          enum: ["CREATED", "PAID", "VALIDATED", "EXPIRED", "CANCELLED"] 
        },
        price: { bsonType: "decimal" },
        purchaseDate: { bsonType: "date" },
        validFrom: { bsonType: "date" },
        validUntil: { bsonType: "date" },
        tripDetails: {
          bsonType: "object",
          properties: {
            tripId: { bsonType: "string" },
            routeId: { bsonType: "string" },
            boardingStop: { bsonType: "string" },
            destinationStop: { bsonType: "string" }
          }
        },
        qrCode: { bsonType: "string" }
      }
    }
  }
});

// Create other collections
db.createCollection("payments");
db.createCollection("trips");
db.createCollection("notifications");
db.createCollection("service_disruptions");

// Create Indexes
db.users.createIndex({ "email": 1 }, { unique: true });
db.users.createIndex({ "username": 1 }, { unique: true });
db.users.createIndex({ "role": 1 });

db.routes.createIndex({ "routeId": 1 }, { unique: true });
db.routes.createIndex({ "transportType": 1 });

db.tickets.createIndex({ "ticketId": 1 }, { unique: true });
db.tickets.createIndex({ "userId": 1 });
db.tickets.createIndex({ "status": 1 });
db.tickets.createIndex({ "validFrom": 1, "validUntil": 1 });

db.payments.createIndex({ "paymentId": 1 }, { unique: true });
db.payments.createIndex({ "userId": 1 });

print("Transport Ticketing Database initialized successfully!");