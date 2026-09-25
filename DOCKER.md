# Docker notes

Docker images are compiled Spring Boot JARs (not source). They are an optional way to run the stack.

## Start / stop

Requires Docker Desktop (or Docker Engine).

```bat
docker-start.bat
```

Loads `eazybank-docker-images.tar` when images are missing, then `docker compose up -d`.

```bat
docker-stop.bat
```

| URL | |
|---|---|
| Gateway | http://localhost:8072 |
| Swagger | http://localhost:8072/swagger-ui.html |
| Eureka | http://localhost:8070 |

After start, wait until services are healthy (about a minute) before calling APIs or `test-all.bat`.

Do not run `start-all.bat` and Docker together — they use the same host ports.

## Layout

| File | Role |
|---|---|
| [Dockerfile](Dockerfile) | Shared JRE 8 image; `SERVICE` build-arg selects the jar |
| [docker-compose.yml](docker-compose.yml) | Seven services, healthchecks, Eureka/config hostnames |
| `docker-start.bat` | Load images if needed, then up |
| `docker-stop.bat` | Compose down |
| `eazybank-docker-images.tar` | Pre-built images for `docker load` |

Inside Compose, services talk via Docker DNS (`configserver`, `eurekaserver`, …). From the host, use `localhost` ports (8072, etc.).

## Notes

- Base image: `eclipse-temurin:8-jre-jammy`
- Kafka messaging is off (no broker); accounts and message still run as HTTP services
- To change code and run again without Docker, use `build.bat` and `start-all.bat` instead
