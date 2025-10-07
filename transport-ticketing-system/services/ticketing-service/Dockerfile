FROM ballerina/ballerina:2201.9.0

WORKDIR /app

COPY Ballerina.toml .
COPY Config.toml .
COPY main.bal .

RUN bal build

EXPOSE 9092

CMD bal run