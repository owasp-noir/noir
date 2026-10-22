package com.example.app.services;

import com.vaadin.flow.server.auth.AnonymousAllowed;
import com.vaadin.hilla.BrowserCallable;
import jakarta.annotation.security.RolesAllowed;

@BrowserCallable @AnonymousAllowed
public class UserEndpoint {
  public String findUser(String name) { return name; }

  @RolesAllowed("ADMIN")
  public void deleteUser(Long id, boolean hard) {}

  public static String version() { return "1"; }

  private String helper() { return ""; }
}
