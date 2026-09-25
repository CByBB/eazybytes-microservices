# Eazy Bank

A banking platform split into Spring Boot microservices. Callers talk to the API gateway; the gateway routes to accounts, cards, and loans.

```
Caller
  → gatewayserver   (8072)  routing
    → eurekaserver  (8070)  service discovery
    → accounts      (8080)  customers and accounts
    → cards         (9000)  credit cards
    → loans         (8090)  loans
    → message       (9010)  notifications
    → configserver  (8071)  central config
```

The app targets **Java 8** bytecode (**Spring Boot 2.7**). The same JARs run on **JDK 8, 11, and 17**. This package includes a portable JDK 8 and Maven under `tools/` (no system Java install required for the non-Docker path).

## Services

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

## Run without Docker

Uses the bundled JDK/Maven under `tools/`.

1. Open this folder in your IDE (`.vscode/settings.json` points at `tools/` when present).
2. Build, then start every service:

```bat
build.bat
start-all.bat
```

Stop:

```bat
start-all.bat stop
```

or `stop-all.bat`.

After code changes, run `build.bat` again, then restart with `start-all.bat stop` and `start-all.bat`.

Optional API check (stack must be up; wait about a minute after start so Eureka is ready):

```bat
test-all.bat
```

| Script | What it does |
|---|---|
| **`build.bat`** | Compiles with bundled JDK/Maven (`tools/`) |
| **`start-all.bat`** | Starts all services as Java processes, waits until ports are ready. Logs under `logs/` |
| **`start-all.bat stop`** / **`stop-all.bat`** | Stops those processes |
| **`test-all.bat`** | API checks through the gateway |

## Run with Docker

Requires **Docker Desktop** (or Docker Engine) already installed.

```bat
docker-start.bat
```

Loads `eazybank-docker-images.tar` if images are not present yet, then starts the stack.

Stop:

```bat
docker-stop.bat
```

Do not run `start-all.bat` and Docker at the same time (same host ports). After `docker-start.bat`, wait until the gateway is healthy before `test-all.bat`.

More Compose notes: [DOCKER.md](DOCKER.md).

| Script | What it does |
|---|---|
| **`docker-start.bat`** | Load images if needed, then `docker compose up -d` |
| **`docker-stop.bat`** | `docker compose down` |

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

Import `Microservices.postman_collection.json` for sample API calls. Gateway routes are open.

## Repository layout

```
eazybank/
├── pom.xml
├── eazy-bom/
├── accounts/ cards/ loans/ message/
├── configserver/ eurekaserver/ gatewayserver/
├── tools/                 # portable JDK 8 + Maven + local m2
├── scripts/               # internal helpers (used by build/start)
├── build.bat
├── start-all.bat / stop-all.bat
├── test-all.bat
├── Dockerfile / docker-compose.yml
├── eazybank-docker-images.tar
├── docker-start.bat / docker-stop.bat
└── DOCKER.md
```

## Config

Each service can load optional config from the config server. Profile files live in `configserver/src/main/resources/config/` (native classpath; no Git remote).
