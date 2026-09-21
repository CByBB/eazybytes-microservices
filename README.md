# Eazy Bank

A banking platform split into Spring Boot microservices. Clients talk to the API gateway; the gateway routes to accounts, cards, and loans. Config, discovery, security, messaging, and observability sit around those services.

```
Client
  → gatewayserver   (8072)  routing, JWT, rate limit
    → eurekaserver  (8070)  service discovery
    → accounts      (8080)  customers and accounts
    → cards         (9000)  credit cards
    → loans         (8090)  loans
    → message               Kafka notifications
    → configserver  (8071)  central config
```

## Repository layout

```
eazybank/
├── pom.xml                 # aggregator
├── eazy-bom/               # shared BOM + common library
├── accounts/
├── cards/
├── loans/
├── configserver/
├── eurekaserver/
├── gatewayserver/
├── message/
├── docker-compose/         # local stack (default / qa / prod)
└── Microservices.postman_collection.json
```

| Service | Role |
|---|---|
| **accounts** | Customers and accounts; calls cards and loans via OpenFeign |
| **cards** | Credit-card APIs |
| **loans** | Loan APIs |
| **configserver** | Spring Cloud Config |
| **eurekaserver** | Netflix Eureka registry |
| **gatewayserver** | Spring Cloud Gateway, Keycloak JWT, Redis rate limiting |
| **message** | Async notifications over Kafka |

Also included: Resilience4j (circuit breaker, retry, rate limiter), Actuator, Prometheus, OpenTelemetry.

## Prerequisites

- Java 21
- Maven 3.9+
- Docker Desktop

## Build

Install the BOM and common library first, then the rest:

```bash
mvn -f eazy-bom/pom.xml clean install -DskipTests
mvn clean install -DskipTests
```

Docker images (Google Jib, tag `latest`):

```bash
mvn -pl accounts,cards,loans,configserver,eurekaserver,gatewayserver,message compile jib:dockerBuild
```

## Run the stack

Default profile (H2 inside each service):

```bash
docker compose -f docker-compose/default/docker-compose.yml up
```

QA or prod config profiles:

```bash
docker compose -f docker-compose/qa/docker-compose.yml up
docker compose -f docker-compose/prod/docker-compose.yml up
```

Without Docker, start infrastructure first (Kafka, Redis, Keycloak), then each service with `mvn spring-boot:run` in this order: `configserver` → `eurekaserver` → `accounts` / `cards` / `loans` / `message` → `gatewayserver`.

## Local URLs

| What | URL |
|---|---|
| API gateway | http://localhost:8072 |
| Eureka | http://localhost:8070 |
| Config server | http://localhost:8071 |
| Keycloak | http://localhost:7080 (`admin` / `admin`) |
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090 |

Import `Microservices.postman_collection.json` for sample API calls. GET routes on the gateway are open; write routes need a Keycloak JWT with role `ACCOUNTS`, `CARDS`, or `LOANS`.

## Config

Each service loads optional config from `http://localhost:8071/`. Profile files live in `configserver/src/main/resources/config/` (`accounts.yml`, `accounts-qa.yml`, `accounts-prod.yml`, and the same for cards/loans).
