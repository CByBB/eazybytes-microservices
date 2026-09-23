package com.eazybytes.configserver;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.servers.Server;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.config.server.EnableConfigServer;

@SpringBootApplication
@EnableConfigServer
@OpenAPIDefinition(
		info = @Info(
				title = "Config Server API",
				description = "Spring Cloud Config. Other services load YAML from here; it is not a banking API.",
				version = "v1"
		),
		servers = {
				@Server(url = "/eazybank/configserver", description = "API gateway"),
				@Server(url = "/", description = "Direct service")
		}
)
public class ConfigserverApplication {

	public static void main(String[] args) {
		SpringApplication.run(ConfigserverApplication.class, args);
	}

}
