// infrastructure/mongodb/init-mongo.js
// This script runs when MongoDB starts for the first time
// It creates our database structure and indexes for optimal performance

// Switch to our application database
db = db.getSiblingDB('transport_ticketing');

print('Initializing transport_ticketing database...');

// Create users collection with indexes
db.createCollection('users');
// Index on email ensures each email is unique and makes login queries fast
db.users.createIndex({ 'email': 1 }, { unique: true });
// Index on userId for fast lookups when other services reference users
db.users.createIndex({ 'userId': 1 }, { unique: true });
print('Created users collection with indexes');

// Create routes collection (bus and train routes)
db.createCollection('routes');
db.routes.createIndex({ 'routeId': 1 }, { unique: true });
// Compound index for finding active routes of a specific type
db.routes.createIndex({ 'active': 1, 'routeType': 1 });
print('Created routes collection with indexes');

// Create trips collection (scheduled departures on routes)
db.createCollection('trips');
db.trips.createIndex({ 'tripId': 1 }, { unique: true });
// Index for finding all trips on a specific route
db.trips.createIndex({ 'routeId': 1 });
// Compound index for finding trips on specific days
db.trips.createIndex({ 'routeId': 1, 'days': 1 });
print('Created trips collection with indexes');

// Create tickets collection
db.createCollection('tickets');
db.tickets.createIndex({ 'ticketId': 1 }, { unique: true });
// Index for finding all tickets for a user
db.tickets.createIndex({ 'userId': 1 });
// Compound index for finding valid tickets
db.tickets.createIndex({ 'status': 1, 'validUntil': 1 });
// Index for finding tickets for a specific trip
db.tickets.createIndex({ 'tripId': 1 });
print('Created tickets collection with indexes');

// Create payments collection
db.createCollection('payments');
db.payments.createIndex({ 'paymentId': 1 }, { unique: true });
// Index for finding payments for a ticket
db.payments.createIndex({ 'ticketId': 1 });
// Index for finding all payments by a user
db.payments.createIndex({ 'userId': 1 });
// Compound index for payment reconciliation
db.payments.createIndex({ 'status': 1, 'timestamp': 1 });
print('Created payments collection with indexes');

// Create service_disruptions collection
db.createCollection('service_disruptions');
db.service_disruptions.createIndex({ 'disruptionId': 1 }, { unique: true });
// Index for finding active disruptions
db.service_disruptions.createIndex({ 'active': 1 });
// Index for finding disruptions on a route
db.service_disruptions.createIndex({ 'routeId': 1, 'active': 1 });
print('Created service_disruptions collection with indexes');

// Insert some sample data for testing
db.routes.insertOne({
    routeId: 'ROUTE_SAMPLE_001',
    name: 'Airport Express',
    routeType: 'TRAIN',
    stops: [
        { stopId: 'STOP_001', name: 'Central Station', stopOrder: 1 },
        { stopId: 'STOP_002', name: 'Airport Terminal 1', stopOrder: 2 },
        { stopId: 'STOP_003', name: 'Airport Terminal 2', stopOrder: 3 }
    ],
    active: true,
    createdAt: new Date()
});

db.trips.insertOne({
    tripId: 'TRIP_SAMPLE_001',
    routeId: 'ROUTE_SAMPLE_001',
    departureTime: '06:00',
    arrivalTime: '06:45',
    days: ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'],
    capacity: 200,
    currentOccupancy: 0,
    createdAt: new Date()
});

print('Database initialization complete!');
print('Sample route and trip created for testing.');