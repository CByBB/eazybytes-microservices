package com.eazybytes.message.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api")
@Tag(name = "Message", description = "Notification worker status")
public class MessageController {

    @GetMapping("/info")
    @Operation(summary = "Message service status")
    public Map<String, Object> info() {
        return Map.of(
                "service", "message",
                "messagingEnabled", false,
                "note", "Kafka is disabled locally. This service stays up as an HTTP app."
        );
    }
}
