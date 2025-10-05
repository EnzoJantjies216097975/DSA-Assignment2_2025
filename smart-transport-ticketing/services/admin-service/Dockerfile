# services/admin-service/Dockerfile
FROM ballerina/ballerina:2201.12.9

WORKDIR /app

# Copy Ballerina project files
COPY Ballerina.toml .
COPY Dependencies.toml .
COPY Config.toml .
COPY main.bal .

# Build the Ballerina project
RUN bal build

# Expose the service port
EXPOSE 9090

# Run the service
CMD ["bal", "run", "target/bin/admin_service.jar"]