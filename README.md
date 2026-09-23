# Eazy Bank

A banking platform split into Spring Boot microservices. Clients talk to the API gateway; the gateway routes to accounts, cards, and loans.

This project runs **locally with Java and Maven only**. It does not use Docker.

```
Client
  → gatewayserver   (8072)  routing
    → eurekaserver  (8070)  service discovery
    → accounts      (8080)  customers and accounts
    → cards         (9000)  credit cards
    → loans         (8090)  loans
    → message       (9010)  notifications
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
└── Microservices.postman_collection.json
```

| Service | Role |
|---|---|
| **accounts** | Customers and accounts; calls cards and loans via OpenFeign |
| **cards** | Credit-card APIs |
| **loans** | Loan APIs |
| **configserver** | Spring Cloud Config |
| **eurekaserver** | Netflix Eureka registry |
| **gatewayserver** | Spring Cloud Gateway |
| **message** | Async notifications |

Each business service uses an in-memory H2 database.

## Prerequisites

- Java 21
- Maven 3.9+

## Build

From the repo root, one command is enough. It builds `eazy-bom` first, then every service:

```bash
mvn clean install -DskipTests
```

You do not need a separate `eazy-bom` command first. Run this after you clone the repo, or after you change code. It does not start the servers.

### Install each module separately

Use these when you only changed one service. `-am` also installs that module’s dependencies (`eazy-bom` / `common`).

```bash
mvn -pl eazy-bom clean install -DskipTests
mvn -pl configserver -am clean install -DskipTests
mvn -pl eurekaserver -am clean install -DskipTests
mvn -pl accounts -am clean install -DskipTests
mvn -pl cards -am clean install -DskipTests
mvn -pl loans -am clean install -DskipTests
mvn -pl message -am clean install -DskipTests
mvn -pl gatewayserver -am clean install -DskipTests
```

| Command | What it installs |
|---|---|
| `mvn -pl eazy-bom clean install -DskipTests` | Shared BOM and `common` library |
| `mvn -pl configserver -am clean install -DskipTests` | Config server |
| `mvn -pl eurekaserver -am clean install -DskipTests` | Eureka |
| `mvn -pl accounts -am clean install -DskipTests` | Accounts |
| `mvn -pl cards -am clean install -DskipTests` | Cards |
| `mvn -pl loans -am clean install -DskipTests` | Loans |
| `mvn -pl message -am clean install -DskipTests` | Message |
| `mvn -pl gatewayserver -am clean install -DskipTests` | Gateway |

## Run

From the repo root (Git Bash):

```bash
./start-all.sh
```

That starts every service in order and waits until each port is ready. Logs go to `logs/`. Each log file is truncated on start and capped at 2MB so Kafka or Maven output cannot grow one file without bound. Kafka messaging is off locally (there is no broker); accounts and message still start as normal HTTP services. Stop them with:

```bash
./start-all.sh stop
```

After the stack is up, call every OpenAPI operation through the gateway:

```bash
./test-all.sh
```

That covers accounts, cards, loans, customer details, message, gateway fallback, and every config-server path including encrypt/decrypt. It then checks that no documented operation was skipped. Use it after a Java or dependency change. It exits `0` if everything passed.

### Run each service separately

Use a new terminal for each command, from the repo root, in this order. Wait until a service finishes starting before you start the next one.

```bash
mvn -pl configserver spring-boot:run
mvn -pl eurekaserver spring-boot:run
mvn -pl accounts spring-boot:run
mvn -pl cards spring-boot:run
mvn -pl loans spring-boot:run
mvn -pl message spring-boot:run
mvn -pl gatewayserver spring-boot:run
```

| Command | Service | Port |
|---|---|---|
| `mvn -pl configserver spring-boot:run` | Config server | 8071 |
| `mvn -pl eurekaserver spring-boot:run` | Eureka | 8070 |
| `mvn -pl accounts spring-boot:run` | Accounts | 8080 |
| `mvn -pl cards spring-boot:run` | Cards | 9000 |
| `mvn -pl loans spring-boot:run` | Loans | 8090 |
| `mvn -pl message spring-boot:run` | Message | 9010 |
| `mvn -pl gatewayserver spring-boot:run` | Gateway | 8072 |

## Local URLs

| What | URL |
|---|---|
| API gateway | http://localhost:8072 |
| Swagger UI | http://localhost:8072/swagger-ui.html |
| Eureka dashboard | http://localhost:8070 |
| Config server | http://localhost:8071 |
| Accounts | http://localhost:8080 |
| Cards | http://localhost:9000 |
| Loans | http://localhost:8090 |
| Message | http://localhost:9010 |

Open http://localhost:8072/swagger-ui.html for Springdoc Swagger UI. The dropdown lists accounts, cards, loans, message, configserver, and gateway. Eureka is a registry UI at http://localhost:8070, not a REST API, so it is not in that list.

Import `Microservices.postman_collection.json` for sample API calls. Gateway routes are open.

## Config

Each service loads optional config from `http://localhost:8071/`. Profile files live in `configserver/src/main/resources/config/` (`accounts.yml`, `accounts-qa.yml`, `accounts-prod.yml`, and the same for cards/loans).
