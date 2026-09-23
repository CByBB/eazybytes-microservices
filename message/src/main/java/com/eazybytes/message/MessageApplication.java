package com.eazybytes.message;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.servers.Server;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(excludeName = {
		"org.springframework.boot.autoconfigure.kafka.KafkaAutoConfiguration",
		"org.springframework.cloud.stream.binder.kafka.config.KafkaBinderConfiguration"
})
@OpenAPIDefinition(
		info = @Info(
				title = "Message service API",
				description = "Notification worker. Kafka is off in this local setup, so this service exposes status only.",
				version = "v1"
		),
		servers = {
				@Server(url = "/eazybank/message", description = "API gateway"),
				@Server(url = "/", description = "Direct service")
		}
)
public class MessageApplication {

	public static void main(String[] args) {
		SpringApplication.run(MessageApplication.class, args);
	}

}
