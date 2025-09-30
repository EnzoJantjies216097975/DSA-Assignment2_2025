db = db.getSiblingDB('transport_db');

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
        notifications: {
          bsonType: "object",
          properties: {
            email: { bsonType: "bool" },
            sms: { bsonType: "bool" },
            push: { bsonType: "bool" }
          }
        },
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
            required: ["stopId", "stopName"],
            properties: {
              stopId: { bsonType: "string" },
              stopName: { bsonType: "string" },
              arrivalTime: { bsonType: "string" },
              departureTime: { bsonType: "string" }
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

// Create all other collections similarly...

// Create Indexes
db.users.createIndex({ "username": 1 }, { unique: true });
db.users.createIndex({ "email": 1 }, { unique: true });
db.users.createIndex({ "role": 1 });

db.routes.createIndex({ "routeId": 1 }, { unique: true });
db.routes.createIndex({ "transportType": 1 });
db.routes.createIndex({ "isActive": 1 });

// Add other indexes...

print("Database schema initialized successfully!");