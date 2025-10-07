#!/bin/bash

echo "🚀 Setting up Transport Ticketing System"
echo "========================================"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker is running${NC}"

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}❌ docker-compose.yml not found. Are you in the project root?${NC}"
    exit 1
fi

echo -e "${GREEN}✅ docker-compose.yml found${NC}"

# Build and start services
echo -e "\n${YELLOW}📦 Building and starting services...${NC}"
docker-compose up -d --build

# Wait for services to be healthy
echo -e "\n${YELLOW}⏳ Waiting for services to initialize (60 seconds)...${NC}"
sleep 10

# Check service health
echo -e "\n${YELLOW}🏥 Checking service health...${NC}"

services=(
    "passenger-service:9090"
    "transport-service:9091"
    "ticketing-service:9092"
    "payment-service:9093"
    "notification-service:9094"
    "admin-service:9095"
)

for service in "${services[@]}"; do
    IFS=':' read -r name port <<< "$service"
    if curl -s "http://localhost:${port}/${name}/health" > /dev/null; then
        echo -e "${GREEN}✅ ${name} is healthy${NC}"
    else
        echo -e "${RED}❌ ${name} is not responding${NC}"
    fi
done

# Check Kafka
echo -e "\n${YELLOW}📡 Checking Kafka...${NC}"
if docker-compose ps kafka | grep -q "Up"; then
    echo -e "${GREEN}✅ Kafka is running${NC}"
else
    echo -e "${RED}❌ Kafka is not running${NC}"
fi

# Check MongoDB
echo -e "\n${YELLOW}🍃 Checking MongoDB...${NC}"
if docker-compose ps mongodb | grep -q "Up"; then
    echo -e "${GREEN}✅ MongoDB is running${NC}"
else
    echo -e "${RED}❌ MongoDB is not running${NC}"
fi

echo -e "\n${GREEN}✨ Setup complete!${NC}"
echo -e "\n${YELLOW}📝 Next steps:${NC}"
echo "1. Wait 30-60 seconds for all services to fully initialize"
echo "2. Test with: ./scripts/test-system.sh"
echo "3. View logs: docker-compose logs -f"
echo "4. Stop system: docker-compose down"
echo -e "\n${YELLOW}🌐 Service URLs:${NC}"
echo "  • Passenger Service: http://localhost:9090/passenger/health"
echo "  • Transport Service: http://localhost:9091/transport/health"
echo "  • Ticketing Service: http://localhost:9092/ticketing/health"
echo "  • Payment Service:   http://localhost:9093/payment/health"
echo "  • Notification Service: http://localhost:9094/notification/health"
echo "  • Admin Service:     http://localhost:9095/admin/health"