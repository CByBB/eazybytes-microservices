# Shared image for every Eazy Bank service. Build with:
#   docker build -f Dockerfile --build-arg SERVICE=accounts -t eazybank/accounts:offline .
FROM eclipse-temurin:8-jre-jammy

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

ARG SERVICE
COPY ${SERVICE}/target/${SERVICE}-0.0.1-SNAPSHOT.jar app.jar

ENTRYPOINT ["java","-jar","/app/app.jar"]
