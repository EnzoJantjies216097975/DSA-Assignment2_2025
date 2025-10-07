FROM ballerina/ballerina:2201.9.0

WORKDIR /app

# Copy Ballerina project files
COPY Ballerina.toml .
COPY main.bal .

# Build the Ballerina project
RUN bal build

# Expose service port
EXPOSE 9090

# Run the service
CMD bal run