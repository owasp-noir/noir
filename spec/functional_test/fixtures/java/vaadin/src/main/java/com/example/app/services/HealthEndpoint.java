package com.example.app.services;

import org.springframework.boot.actuate.endpoint.annotation.Endpoint;
import org.springframework.boot.actuate.endpoint.annotation.ReadOperation;

@Endpoint(id = "custom")
public class HealthEndpoint {
  @ReadOperation
  public String health() { return "up"; }
}
