#!/bin/bash

echo "Starting Kafka topic creation..."
echo "Waiting for Kafka to be ready..."

MAX_ATTEMPTS=30
ATTEMPT=0
KAFKA_SERVER="kafka:9092"

# Wait for Kafka to be ready
until kafka-topics.sh --list --bootstrap-server $KAFKA_SERVER > /dev/null 2>&1; do
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        echo "ERROR: Kafka not ready after $MAX_ATTEMPTS attempts"
        exit 1
    fi
    echo "Waiting for Kafka... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 5
done

echo "Kafka is ready! Creating topics..."

# Create all essential topics
kafka-topics.sh --create --topic ticket.requests --bootstrap-server $KAFKA_SERVER --partitions 3 --replication-factor 1 --if-not-exists
kafka-topics.sh --create --topic payments.processed --bootstrap-server $KAFKA_SERVER --partitions 3 --replication-factor 1 --if-not-exists
kafka-topics.sh --create --topic ticket.validations --bootstrap-server $KAFKA_SERVER --partitions 3 --replication-factor 1 --if-not-exists
kafka-topics.sh --create --topic passenger.registrations --bootstrap-server $KAFKA_SERVER --partitions 2 --replication-factor 1 --if-not-exists

# Additional topics needed by services
kafka-topics.sh --create --topic user.events --bootstrap-server $KAFKA_SERVER --partitions 2 --replication-factor 1 --if-not-exists
kafka-topics.sh --create --topic route.events --bootstrap-server $KAFKA_SERVER --partitions 2 --replication-factor 1 --if-not-exists
kafka-topics.sh --create --topic schedule.updates --bootstrap-server $KAFKA_SERVER --partitions 3 --replication-factor 1 --if-not-exists
kafka-topics.sh --create --topic payment.events --bootstrap-server $KAFKA_SERVER --partitions 2 --replication-factor 1 --if-not-exists
kafka-topics.sh --create --topic notification.triggers --bootstrap-server $KAFKA_SERVER --partitions 2 --replication-factor 1 --if-not-exists
kafka-topics.sh --create --topic admin.actions --bootstrap-server $KAFKA_SERVER --partitions 2 --replication-factor 1 --if-not-exists
kafka-topics.sh --create --topic ticket.cancellations --bootstrap-server $KAFKA_SERVER --partitions 2 --replication-factor 1 --if-not-exists

echo "Topics created successfully!"
echo "Listing all topics:"
kafka-topics.sh --list --bootstrap-server $KAFKA_SERVER