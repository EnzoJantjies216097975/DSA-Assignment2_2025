FROM ballerina/ballerina:2201.12.9

WORKDIR /app

# Copy Ballerina project files
COPY Ballerina.toml .
COPY *.bal .

# Build the Ballerina project
RUN bal build

# Run the client application
CMD ["bal", "run", "target/bin/cli_client.jar"]