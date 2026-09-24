# Docker offline package

**Docker images do not contain source code.** They only contain compiled Spring Boot JARs ready to run.

| Package | Contents | Offline develop (edit + rebuild)? | Offline run? |
|---|---|---|---|
| `eazybank-offline.tar` via **`package-offline.bat`** | SOURCE + `tools/` + image tar + scripts | **Yes** (`build.bat` / `start-all.bat`) | Yes — jars *or* Docker |
| `eazybank-docker-offline.tar` via `docker-prepare-offline.bat` | SOURCE + image tar (**no** `tools/`) | No (cannot rebuild without JDK/Maven) | Yes — Docker only |
| `eazybank-docker-images.tar` alone | Images only | No | Only with compose scripts |

Prefer **`package-offline.bat`** so one `.tar` supports both development and Docker run. See [README.md](README.md).

## Online PC — full kit (recommended)

```bat
prepare-offline.bat
package-offline.bat
```

That builds jars with bundled Maven, builds/saves Docker images, and packs **source + tools + images** into **`eazybank-offline.tar`**.

## Online PC — Docker-only .tar (optional)

```bat
docker-prepare-offline.bat
```

Creates **`eazybank-docker-offline.tar`** (source + images, no JDK/Maven). Use only if you do not need offline rebuilds.

## Offline PC — Docker Desktop

1. Extract: `tar -xf eazybank-offline.tar` (or the Docker-only `.tar`)
2. From the `eazybank` folder:

```bat
docker-start.bat
```

Loads images if needed, then `docker compose up -d`.

| URL | |
|---|---|
| Gateway | http://localhost:8072 |
| Swagger | http://localhost:8072/swagger-ui.html |
| Eureka | http://localhost:8070 |

Optional API regression: `test-all.bat`

Stop: `docker-stop.bat`

## Offline develop without Docker

If you used `package-offline.bat`, you can ignore Docker and use:

```bat
build.bat
start-all.bat
```

No Docker required. Stop with `start-all.bat stop` or `stop-all.bat`.

## Layout

| File | Role |
|---|---|
| [Dockerfile](Dockerfile) | Shared JRE 21 image; `SERVICE` build-arg selects the jar |
| [docker-compose.yml](docker-compose.yml) | Seven services, healthchecks, Eureka/config hostnames |
| `package-offline.bat` | **Preferred:** source + tools + images → `eazybank-offline.tar` |
| `docker-prepare-offline.bat` | Docker-only `.tar` (no tools) |
| `docker-start.bat` | Offline: load + up |
| `docker-stop.bat` | `compose down` |

Inside Compose, services talk via Docker DNS (`configserver`, `eurekaserver`, …). The host still uses `localhost` ports (8072, etc.).

## Notes

- First build on the online PC needs network to pull `eclipse-temurin:21-jre-jammy`.
- Kafka messaging is off (no broker); accounts and message still run as HTTP services.
- After code changes offline: rebuild with `build.bat` + `start-all.bat`, **or** rebuild jars then `docker compose build` (base image must already be loaded from the tar).
