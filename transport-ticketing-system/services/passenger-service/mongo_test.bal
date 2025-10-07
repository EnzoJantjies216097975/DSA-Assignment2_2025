import ballerinax/mongodb;
import ballerina/log;
import ballerina/io;

configurable string mongoHost = "mongodb";
configurable int mongoPort = 27017;
configurable string mongoUsername = "admin";
configurable string mongoPassword = "password123";
configurable string mongoDatabase = "transport_db";

public function main() returns error? {
    io:println("Testing MongoDB connection...");
    
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
    
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    io:println("✅ Successfully connected to MongoDB!");
    
    // Try to list collections
    string[] collections = check db->listCollectionNames();
    io:println("✅ Collections: " + collections.toString());
    
    return ();
}