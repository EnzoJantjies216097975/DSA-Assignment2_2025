FROM ballerina/ballerina:2201.8.5

WORKDIR /home/ballerina

COPY passenger-service.bal .
COPY config.toml .

EXPOSE 8081

CMD ["bal", "run", "passenger-service.bal"]