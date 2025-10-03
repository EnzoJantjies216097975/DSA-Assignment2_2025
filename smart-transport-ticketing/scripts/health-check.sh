#!/bin/bash

echo "Checking service health..."

services=(
  "http://localhost:8081/passenger/health"
  "http://localhost:8082/transport/health"
  "http://localhost:8083/ticketing/health"
  "http://localhost:8084/payment/health"
  "http://localhost:8085/notification/health"
  "http://localhost:9090/admin/health"
)

for service in "${services[@]}"; do
  response=$(curl -s -o /dev/null -w "%{http_code}" $service)

  if [ $response -eq 200 ]; then
    echo "$service is healthy"
  else
    echo "$service is unhealthy (HTTP status code: $response)"
  fi
done