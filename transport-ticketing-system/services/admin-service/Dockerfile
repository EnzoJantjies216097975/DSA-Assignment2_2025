FROM ballerina/ballerina:2201.9.0

WORKDIR /app

COPY Ballerina.toml .
COPY main.bal .

RUN bal build

EXPOSE 9095

CMD bal run