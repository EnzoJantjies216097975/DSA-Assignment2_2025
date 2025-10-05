# services/validation-service/Dockerfile
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
EXPOSE 8087

# Run the service
CMD ["bal", "run", "target/bin/validation_service.jar"]