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

**Images do not contain source.** Docker images are compiled JARs only.

The app targets **Java 8** bytecode (**Spring Boot 2.7**). The same JARs run on **JDK 8, 11, and 17**. The offline kit bundles **JDK 8** under `tools/` for develop/run without a system install.

For **offline development** (edit + rebuild + run) you need `tools/` — that is what `eazybank-offline.tar` is for. Docker is an optional second way to *run* the stack.

## Offline portable kit (recommended)

One `.tar` covers **edit + rebuild** and **Docker run** on a Windows PC with no network.

### Online PC (once)

```bat
prepare-offline.bat
package-offline.bat
```

Creates **`eazybank-offline.tar`** = project SOURCE + `tools/` (JDK 8, Maven, local `m2`) + `eazybank-docker-images.tar` + compose/scripts.

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

## Scripts (`.bat` files)

### Online PC — prepare the delivery

| Script | What it does |
|---|---|
| **`prepare-offline.bat`** | Downloads portable JDK 8 and Maven into `tools/`, fills the local Maven cache (`tools/m2`), and proves an offline build works. Needs network. Run this first. |
| **`package-offline.bat`** | Builds jars with `tools/`, builds and saves Docker images, then packs **source + `tools/` + images + scripts** into **`eazybank-offline.tar`**. This is the file to copy to the offline PC. |
| **`docker-prepare-offline.bat`** | Optional. Builds a Docker-only `.tar` (source + images, **no** `tools/`). Prefer `package-offline.bat` when offline rebuild is required. |

### Offline PC — develop and run without Docker

| Script | What it does |
|---|---|
| **`build.bat`** | Compiles the project offline using bundled JDK/Maven and `tools/m2` (`mvn -o`). Run after code changes. |
| **`start-all.bat`** | Starts every service as a Java process (no Docker), in order, and waits until ports are ready. Logs go under `logs/`. |
| **`start-all.bat stop`** | Stops all services started by `start-all.bat`. |
| **`stop-all.bat`** | Same as `start-all.bat stop`. |
| **`test-all.bat`** | Runs API checks through the gateway. The stack must already be up. |

### Offline PC — run with Docker

| Script | What it does |
|---|---|
| **`docker-start.bat`** | Loads `eazybank-docker-images.tar` if images are missing, then starts the stack with `docker compose up -d`. Needs Docker Desktop. |
| **`docker-stop.bat`** | Stops the Docker Compose stack (`docker compose down`). |

`scripts/offline-env.bat` is an internal helper used by `build.bat` and `start-all.bat` to point at `tools/`. Do not run it by hand.

## Repository layout

```
eazybank/
├── pom.xml
├── eazy-bom/
├── accounts/ cards/ loans/ message/
├── configserver/ eurekaserver/ gatewayserver/
├── tools/                      # JDK 8 + Maven + m2 (from prepare-offline; not in git)
├── scripts/                    # internal helpers (offline-env.bat)
├── prepare-offline.bat
├── package-offline.bat
├── build.bat
├── start-all.bat / stop-all.bat
├── test-all.bat
├── Dockerfile / docker-compose.yml
├── docker-prepare-offline.bat
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
