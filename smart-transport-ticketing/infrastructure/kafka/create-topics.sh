echo "Waiting for Kafka to be ready..."
sleep 15

 Create topic for ticket purchase requests
# Partitions=3 means Kafka can process 3 ticket requests in parallel
echo "Creating ticket.requests topic..."
kafka-topics.sh --create \
    --topic ticket.requests \
    --bootstrap-server kafka:9092 \
    --partitions 3 \
    --replication-factor 1 \
    --config retention.ms=604800000  # Keep messages for 7 days

# Create topic for payment confirmations
echo "Creating payments.processed topic..."
kafka-topics.sh --create \
    --topic payments.processed \
    --bootstrap-server kafka:9092 \
    --partitions 3 \
    --replication-factor 1

# Create topic for ticket validations (when passengers board)
echo "Creating tickets.validated topic..."
kafka-topics.sh --create \
    --topic tickets.validated \
    --bootstrap-server kafka:9092 \
    --partitions 3 \
    --replication-factor 1

# Create topic for schedule updates
echo "Creating schedule.updates topic..."
kafka-topics.sh --create \
    --topic schedule.updates \
    --bootstrap-server kafka:9092 \
    --partitions 2 \
    --replication-factor 1

# Create topic for service disruptions (delays, cancellations)
echo "Creating service.disruptions topic..."
kafka-topics.sh --create \
    --topic service.disruptions \
    --bootstrap-server kafka:9092 \
    --partitions 2 \
    --replication-factor 1

# Create topic for notifications
echo "Creating notifications.send topic..."
kafka-topics.sh --create \
    --topic notifications.send \
    --bootstrap-server kafka:9092 \
    --partitions 3 \
    --replication-factor 1

echo "All Kafka topics created successfully!"

# List all topics to confirm creation
echo "Listing all topics:"
kafka-topics.sh --list --bootstrap-server kafka:9092

