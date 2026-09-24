# Eazy Bank

A banking platform split into Spring Boot microservices. Clients talk to the API gateway; the gateway routes to accounts, cards, and loans.

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

**Images do not contain source.** Docker images are compiled JARs only.

For **offline development** (edit + rebuild + run) you need the portable `tools/` kit (JDK, Maven, dependency cache) — that is what `eazybank-offline.tar` is for. Docker is an optional second way to *run* the stack.

## Offline portable kit (recommended)

One `.tar` covers **edit + rebuild** and **Docker run** on a Windows PC with no network.

### Online PC (once)

```bat
prepare-offline.bat
package-offline.bat
```

Creates **`eazybank-offline.tar`** = project SOURCE + `tools/` (JDK 21, Maven, local `m2`) + `eazybank-docker-images.tar` + compose/scripts.

Copy **only that `.tar`** to the offline PC.

### Offline PC — develop (no Docker required)

1. Extract: `tar -xf eazybank-offline.tar`
2. Open the `eazybank` folder in Cursor / VS Code / IntelliJ (`.vscode/settings.json` points at `tools/`)
3. After code changes:

```bat
build.bat
start-all.bat
```

Stop:

```bat
start-all.bat stop
```

or `stop-all.bat`. API regression (stack must be up): `test-all.bat`.

### Offline PC — run with Docker (optional)

Requires Docker Desktop already installed.

```bat
docker-start.bat
```

Stop: `docker-stop.bat`. Details: [DOCKER.md](DOCKER.md).

## Repository layout

```
eazybank/
├── pom.xml
├── eazy-bom/
├── accounts/ cards/ loans/ message/
├── configserver/ eurekaserver/ gatewayserver/
├── tools/                      # JDK + Maven + m2 (from prepare-offline; not in git)
├── prepare-offline.bat         # online: download tools, fill m2, prove mvn -o
├── package-offline.bat         # online: one .tar (source + tools + Docker images)
├── build.bat                   # offline: mvn -o clean install
├── start-all.bat / stop-all.bat
├── test-all.bat
├── Dockerfile / docker-compose.yml
├── docker-prepare-offline.bat  # optional Docker-only .tar (no tools/)
├── docker-start.bat / docker-stop.bat
└── DOCKER.md
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

## Config

Each service loads optional config from the config server. Profile files live in `configserver/src/main/resources/config/`. Config is native classpath (no Git remote), so it works offline.
