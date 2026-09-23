package com.eazybytes.gatewayserver.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

@RestController
@Tag(name = "Gateway", description = "Landing page and docs")
public class HomeController {

    @GetMapping(value = "/", produces = MediaType.TEXT_HTML_VALUE)
    @Operation(summary = "Gateway landing page")
    public Mono<String> home() {
        return Mono.just("""
                <!DOCTYPE html>
                <html lang="en">
                <head>
                  <meta charset="UTF-8">
                  <title>Eazy Bank Gateway</title>
                  <style>
                    body { font-family: sans-serif; max-width: 40rem; margin: 3rem auto; color: #1a1a1a; }
                    code, a { font-family: ui-monospace, monospace; }
                    li { margin: 0.4rem 0; }
                  </style>
                </head>
                <body>
                  <h1>Eazy Bank Gateway</h1>
                  <p>This is the API gateway. Use Swagger UI to browse endpoints.</p>
                  <ul>
                    <li><a href="/swagger-ui.html">Swagger UI</a> — accounts, cards, loans, message, config, gateway</li>
                    <li><a href="http://localhost:8070">Eureka dashboard</a> — service registry (not a REST API)</li>
                    <li><a href="/actuator/health">/actuator/health</a></li>
                  </ul>
                </body>
                </html>
                """);
    }
}
