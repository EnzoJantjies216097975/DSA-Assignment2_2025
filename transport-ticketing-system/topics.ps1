# Check the actual messages in the topics
Write-Host "CHECKING ACTUAL KAFKA MESSAGES" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

Write-Host "`n1. Messages in ticket.requests topic:" -ForegroundColor Yellow
docker-compose exec kafka /bin/bash -c "/usr/bin/kafka-console-consumer --bootstrap-server localhost:9092 --topic ticket.requests --from-beginning --max-messages 2 --timeout-ms 5000"

Write-Host "`n2. Messages in payments.processed topic:" -ForegroundColor Yellow
docker-compose exec kafka /bin/bash -c "/usr/bin/kafka-console-consumer --bootstrap-server localhost:9092 --topic payments.processed --from-beginning --max-messages 2 --timeout-ms 5000"