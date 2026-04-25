package com.example.api;

import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.HeaderParam;

public class UserFilter {
    @QueryParam("active")
    private Boolean active;

    @QueryParam("role")
    private String role;

    @HeaderParam("X-Tenant")
    private String tenant;

    public Boolean getActive() { return active; }
    public void setActive(Boolean active) { this.active = active; }

    public String getRole() { return role; }
    public void setRole(String role) { this.role = role; }

    public String getTenant() { return tenant; }
    public void setTenant(String tenant) { this.tenant = tenant; }
}
