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

// Create Routes Collection | OWNED BY TRANSPORT SERVICE
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

// Create Trips Collection | OWNED BY TRANSPORT SERVICE
db.createCollection("trips", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "tripId", "routeId", "departureTime", "arrivalTime", "status"],
      properties: {
        _id: { bsonType: "objectId" },
        tripId: { bsonType: "string" },
        routeId: { bsonType: "string" },
        departureTime: { bsonType: "date" },
        arrivalTime: { bsonType: "date" },
        status: { 
          bsonType: "string", 
          enum: ["SCHEDULED", "DELAYED", "CANCELLED", "IN_PROGRESS", "COMPLETED"] 
        },
        vehicleId: { bsonType: "string" },
        driverId: { bsonType: "string" },
        availableSeats: { bsonType: "int" },
        totalSeats: { bsonType: "int" },
        currentLocation: {
          bsonType: "object",
          properties: {
            latitude: { bsonType: "double" },
            longitude: { bsonType: "double" },
            lastUpdated: { bsonType: "date" }
          }
        },
        delayInfo: {
          bsonType: "object",
          properties: {
            delayMinutes: { bsonType: "int" },
            reason: { bsonType: "string" }
          }
        },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// Create Tickets Collection | OWNED BY TICKETING SERVICE
db.createCollection("tickets", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "ticketId", "userId", "routeId", "ticketType", "status", "purchaseDate"],
      properties: {
        _id: { bsonType: "objectId" },
        ticketId: { bsonType: "string" },
        userId: { bsonType: "string" },
        routeId: { bsonType: "string" },
        tripId: { bsonType: "string" },
        ticketType: { 
          bsonType: "string", 
          enum: ["SINGLE_RIDE", "MULTI_RIDE", "DAY_PASS", "WEEKLY_PASS", "MONTHLY_PASS"] 
        },
        status: { 
          bsonType: "string", 
          enum: ["CREATED", "PENDING_PAYMENT", "PAID", "VALIDATED", "EXPIRED", "CANCELLED"] 
        },
        price: { bsonType: "decimal" },
        ridesRemaining: { bsonType: "int" },
        validFrom: { bsonType: "date" },
        validUntil: { bsonType: "date" },
        purchaseDate: { bsonType: "date" },
        qrCode: { bsonType: "string" },
        validationHistory: {
          bsonType: "array",
          items: {
            bsonType: "object",
            properties: {
              validatedAt: { bsonType: "date" },
              validatorId: { bsonType: "string" },
              tripId: { bsonType: "string" },
              location: { bsonType: "string" }
            }
          }
        },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// Create Payments Collection | OWNED BY PAYMENT SERVICE
db.createCollection("payments", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "paymentId", "userId", "ticketId", "amount", "status", "paymentDate"],
      properties: {
        _id: { bsonType: "objectId" },
        paymentId: { bsonType: "string" },
        userId: { bsonType: "string" },
        ticketId: { bsonType: "string" },
        amount: { bsonType: "decimal" },
        paymentMethod: { 
          bsonType: "string", 
          enum: ["BALANCE", "CARD", "MOBILE_MONEY", "CASH"] 
        },
        status: { 
          bsonType: "string", 
          enum: ["PENDING", "SUCCESS", "FAILED", "REFUNDED"] 
        },
        transactionReference: { bsonType: "string" },
        paymentGateway: { bsonType: "string" },
        failureReason: { bsonType: "string" },
        paymentDate: { bsonType: "date" },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// Create Notifications Collection | OWNED BY NOTIFICATION SERVICE
db.createCollection("notifications", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "notificationId", "userId", "type", "message", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        notificationId: { bsonType: "string" },
        userId: { bsonType: "string" },
        type: { 
          bsonType: "string", 
          enum: ["TICKET_VALIDATED", "SCHEDULE_UPDATE", "PAYMENT_CONFIRMATION", 
                 "SERVICE_DISRUPTION", "TRIP_REMINDER", "ACCOUNT_UPDATE"] 
        },
        title: { bsonType: "string" },
        message: { bsonType: "string" },
        priority: { 
          bsonType: "string", 
          enum: ["LOW", "MEDIUM", "HIGH", "URGENT"] 
        },
        isRead: { bsonType: "bool" },
        readAt: { bsonType: "date" },
        relatedEntityId: { bsonType: "string" },
        relatedEntityType: { bsonType: "string" },
        metadata: { bsonType: "object" },
        channels: {
          bsonType: "array",
          items: { 
            bsonType: "string", 
            enum: ["EMAIL", "SMS", "PUSH", "IN_APP"] 
          }
        },
        deliveryStatus: {
          bsonType: "object",
          properties: {
            email: { bsonType: "string", enum: ["SENT", "DELIVERED", "FAILED", "PENDING"] },
            sms: { bsonType: "string", enum: ["SENT", "DELIVERED", "FAILED", "PENDING"] },
            push: { bsonType: "string", enum: ["SENT", "DELIVERED", "FAILED", "PENDING"] }
          }
        },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// Create Service Disruptions Collection | OWNED BY ADMIN
db.createCollection("serviceDisruptions", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "disruptionId", "type", "severity", "status", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        disruptionId: { bsonType: "string" },
        routeId: { bsonType: "string" },
        tripId: { bsonType: "string" },
        type: { 
          bsonType: "string", 
          enum: ["DELAY", "CANCELLATION", "MAINTENANCE", "EMERGENCY", "WEATHER", "ACCIDENT"] 
        },
        severity: { 
          bsonType: "string", 
          enum: ["LOW", "MEDIUM", "HIGH", "CRITICAL"] 
        },
        status: { 
          bsonType: "string", 
          enum: ["ACTIVE", "RESOLVED", "MONITORING"] 
        },
        title: { bsonType: "string" },
        description: { bsonType: "string" },
        affectedArea: { bsonType: "string" },
        startTime: { bsonType: "date" },
        endTime: { bsonType: "date" },
        estimatedResolutionTime: { bsonType: "date" },
        reportedBy: { bsonType: "string" },
        alternativeRoutes: {
          bsonType: "array",
          items: { bsonType: "string" }
        },
        updates: {
          bsonType: "array",
          items: {
            bsonType: "object",
            properties: {
              timestamp: { bsonType: "date" },
              message: { bsonType: "string" },
              updatedBy: { bsonType: "string" }
            }
          }
        },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// Create Validations Collection | OWNED BY VALIDATOR
db.createCollection("validations", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "validationId", "ticketId", "validatorId", "validatedAt", "success"],
      properties: {
        _id: { bsonType: "objectId" },
        validationId: { bsonType: "string" },
        ticketId: { bsonType: "string" },
        userId: { bsonType: "string" },
        routeId: { bsonType: "string" },
        tripId: { bsonType: "string" },
        validatorId: { bsonType: "string" },
        validatorName: { bsonType: "string" },
        vehicleId: { bsonType: "string" },
        success: { bsonType: "bool" },
        failureReason: { bsonType: "string" },
        location: {
          bsonType: "object",
          properties: {
            latitude: { bsonType: "double" },
            longitude: { bsonType: "double" },
            stopName: { bsonType: "string" }
          }
        },
        deviceInfo: {
          bsonType: "object",
          properties: {
            deviceId: { bsonType: "string" },
            deviceType: { bsonType: "string" },
            osVersion: { bsonType: "string" }
          }
        },
        ridesRemainingAfter: { bsonType: "int" },
        validatedAt: { bsonType: "date" },
        createdAt: { bsonType: "date" }
      }
    }
  }
});

// Create Analytics | Reports Collection | OWNED BY ADMIN
db.createCollection("analyticsReports", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "reportId", "reportType", "generatedAt"],
      properties: {
        _id: { bsonType: "objectId" },
        reportId: { bsonType: "string" },
        reportType: { 
          bsonType: "string", 
          enum: ["SALES", "TRAFFIC", "REVENUE", "USAGE", "PERFORMANCE"] 
        },
        period: { 
          bsonType: "string", 
          enum: ["DAILY", "WEEKLY", "MONTHLY", "QUARTERLY", "YEARLY"] 
        },
        startDate: { bsonType: "date" },
        endDate: { bsonType: "date" },
        data: {
          bsonType: "object",
          properties: {
            totalTicketsSold: { bsonType: "int" },
            totalRevenue: { bsonType: "decimal" },
            totalPassengers: { bsonType: "int" },
            averageOccupancy: { bsonType: "double" },
            peakHours: { bsonType: "array" },
            ticketTypeBreakdown: { bsonType: "object" },
            routePerformance: { bsonType: "array" },
            revenueByRoute: { bsonType: "object" }
          }
        },
        generatedBy: { bsonType: "string" },
        generatedAt: { bsonType: "date" },
        createdAt: { bsonType: "date" }
      }
    }
  }
});

// Create System Logs Collection | OWNED BY ADMIN
db.createCollection("systemLogs", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "logId", "service", "level", "message", "timestamp"],
      properties: {
        _id: { bsonType: "objectId" },
        logId: { bsonType: "string" },
        service: { 
          bsonType: "string", 
          enum: ["PASSENGER", "TRANSPORT", "TICKETING", "PAYMENT", 
                 "NOTIFICATION", "ADMIN", "VALIDATION"] 
        },
        level: { 
          bsonType: "string", 
          enum: ["INFO", "WARN", "ERROR", "DEBUG", "FATAL"] 
        },
        message: { bsonType: "string" },
        errorStack: { bsonType: "string" },
        userId: { bsonType: "string" },
        requestId: { bsonType: "string" },
        metadata: { bsonType: "object" },
        timestamp: { bsonType: "date" }
      }
    }
  }
});

// Create Indexes
db.users.createIndex({ "username": 1 }, { unique: true });
db.users.createIndex({ "email": 1 }, { unique: true });
db.users.createIndex({ "role": 1 });
db.users.createIndex({ "createdAt": 1 });

//Route  INDEXES
db.routes.createIndex({ "routeId": 1 }, { unique: true });
db.routes.createIndex({ "transportType": 1 });
db.routes.createIndex({ "isActive": 1 });
db.routes.createIndex({ "startPoint": 1, "endPoint": 1 });

// TRIP INDEXES
db.trips.createIndex({ "tripId": 1 }, { unique: true });
db.trips.createIndex({ "routeId": 1 });
db.trips.createIndex({ "status": 1, "departureTime": 1 });
db.trips.createIndex({ "departureTime": 1 });
db.trips.createIndex({ "arrivalTime": 1 });
db.trips.createIndex({ "vehicleId": 1 });
db.trips.createIndex({ "driverId": 1 });
db.trips.createIndex({ "status": 1, "departureTime": 1 });
db.trips.createIndex({ "currentLocation.latitude": 1, "currentLocation.longitude": 1 });

//TICKET INDEXES
db.tickets.createIndex({ "ticketId": 1 }, { unique: true });
db.tickets.createIndex({ "userId": 1 });
db.tickets.createIndex({ "routeId": 1 }); 
db.tickets.createIndex({ "tripId": 1 });
db.tickets.createIndex({ "userId": 1, "status": 1 });
db.tickets.createIndex({ "validFrom": 1, "validUntil": 1 });
db.tickets.createIndex({ "purchaseDate": -1 });

//PAYMENT INDEXES
db.payments.createIndex({ "paymentId": 1 }, { unique: true });
db.payments.createIndex({ "userId": 1 });
db.payments.createIndex({ "ticketId": 1 });
db.payments.createIndex({ "status": 1 });
db.payments.createIndex({ "paymentDate": -1 });
db.payments.createIndex({ "userId": 1, "status": 1 });
db.payments.createIndex({ "paymentMethod": 1 });
db.payments.createIndex({ "amount": 1 });
db.payments.createIndex({ "paymentGateway": 1 });


// NOTIFICATION INDEXES
db.notifications.createIndex({ "notificationId": 1 }, { unique: true });
db.notifications.createIndex({ "userId": 1 });
db.notifications.createIndex({ "isRead": 1 });
db.notifications.createIndex({ "type": 1, "createdAt": -1 });
db.notifications.createIndex({ "userId": 1, "isRead": 1 });
db.notifications.createIndex({ "priority": 1 });

// SERVICE DISRUPTION INDEXES
db.serviceDisruptions.createIndex({ "disruptionId": 1 }, { unique: true });
db.serviceDisruptions.createIndex({ "routeId": 1 });
db.serviceDisruptions.createIndex({ "status": 1 });
db.serviceDisruptions.createIndex({ "severity": 1 });
db.serviceDisruptions.createIndex({ "startTime": -1 });

// VALIDATION INDEXES
db.validations.createIndex({ "validationId": 1 }, { unique: true });
db.validations.createIndex({ "ticketId": 1 });
db.validations.createIndex({ "userId": 1 });
db.validations.createIndex({ "validatorId": 1 });
db.validations.createIndex({ "tripId": 1 });
db.validations.createIndex({ "validatedAt": -1 });
db.validations.createIndex({ "success": 1 });

// ANALYTICS/REPORTS INDEXES
db.analyticsReports.createIndex({ "reportId": 1 }, { unique: true });
db.analyticsReports.createIndex({ "reportType": 1 });
db.analyticsReports.createIndex({ "period": 1 });
db.analyticsReports.createIndex({ "generatedAt": -1 });

// SYSTEM LOGS INDEXES
db.systemLogs.createIndex({ "logId": 1 }, { unique: true });
db.systemLogs.createIndex({ "service": 1 });
db.systemLogs.createIndex({ "level": 1 });
db.systemLogs.createIndex({ "timestamp": -1 });
db.systemLogs.createIndex({ "userId": 1 });

// COMPOUND INDEXES FOR COMMON QUERIES
db.tickets.createIndex({ "userId": 1, "validFrom": 1, "validUntil": 1 });
db.trips.createIndex({ "routeId": 1, "status": 1, "departureTime": 1 });
db.validations.createIndex({ "validatorId": 1, "validatedAt": -1 });
db.payments.createIndex({ "userId": 1, "paymentDate": -1 });



print("Database schema initialized successfully!");
print("✓ Created 10 collections with validators");
print("✓ Created 50 PLUS indexes for optimal query performance");
print("✓ Database: transport_db is ready for use");