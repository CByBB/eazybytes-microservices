# Eazy Bank

A banking platform split into Spring Boot microservices. Clients talk to the API gateway; the gateway routes to accounts, cards, and loans.

This project runs **locally with Java and Maven only**. It does not use Docker.

It is designed to run on a **fully offline Windows PC** that has only a browser, Postman, and a code IDE — no system Java or Maven install required — after you prepare a portable kit on an online machine.

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
├── tools/                  # portable JDK + Maven + m2 (created by prepare-offline.bat)
├── scripts/                # internal helpers (not run by hand)
├── prepare-offline.bat
├── package-offline.bat
├── build.bat
├── start-all.bat
├── test-all.bat
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

## Offline Windows kit (recommended)

No system Java, Maven, Git, or Docker is required on the target PC.

### 1. On an online PC (this machine)

Download a portable JDK 21, Maven, and fill a project-local dependency cache:

```bat
prepare-offline.bat
```

Then build the archive to copy:

```bat
package-offline.bat
```

That creates `eazybank-offline.tar` (typically ~0.5–1.5 GB). It includes source, scripts, `tools\jdk`, `tools\maven`, and `tools\m2`. `tools\` is gitignored; only the archive carries those binaries.

### 2. On the offline PC

1. Copy and extract `eazybank-offline.tar` (for example `tar -xf eazybank-offline.tar`).
2. Build (uses only the bundled cache; no network):

```bat
build.bat
```

3. Start every service in order:

```bat
start-all.bat
```

4. Open http://localhost:8072 or Swagger at http://localhost:8072/swagger-ui.html. Import `Microservices.postman_collection.json` into Postman.

5. After code changes, rebuild and restart:

```bat
build.bat
start-all.bat stop
start-all.bat
```

6. Optional full API regression:

```bat
test-all.bat
```

Stop everything with:

```bat
start-all.bat stop
```

### Offline development notes

- Compile and run always go through `build.bat` / `start-all.bat` (or the bundled `tools\maven` with `-o`).
- New Maven dependencies **cannot** be downloaded offline. Add them on an online PC, re-run `prepare-offline.bat`, and re-package.
- IDE autocomplete works only if the Java language support is **already installed** in that IDE. Point Cursor / VS Code at the kit via [`.vscode/settings.json`](.vscode/settings.json). If the Java extension was never installed, use the IDE as an editor and Maven from `cmd`.

## Prerequisites (online / optional system install)

If you are not using the portable kit:

- Java 21
- Maven 3.9+

## Build (system Maven)

From the repo root, one command is enough. It builds `eazy-bom` first, then every service:

```bash
mvn clean install -DskipTests
```

With the portable kit, prefer `build.bat` (offline) instead.

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

### Windows (portable kit)

```bat
build.bat
start-all.bat
```

That starts every service in order and waits until each port is ready. Logs go to `logs/`. Kafka messaging is off locally (there is no broker); accounts and message still start as normal HTTP services. Stop them with:

```bat
start-all.bat stop
```

After the stack is up, call every OpenAPI operation through the gateway:

```bat
test-all.bat
```

### Run each service separately

Use a new terminal for each command, from the repo root, in this order. Wait until a service finishes starting before you start the next one. With the kit, use `tools\maven\bin\mvn.cmd` and jars under each module’s `target\` after `build.bat`.

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

Each service loads optional config from `http://localhost:8071/`. Profile files live in `configserver/src/main/resources/config/` (`accounts.yml`, `accounts-qa.yml`, `accounts-prod.yml`, and the same for cards/loans). Config is native classpath (no Git remote), so it works offline.
