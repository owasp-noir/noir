package com.example.api;

import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.DefaultValue;

public class UserFilter {
    private static final String ACTIVE_PARAM = "active";
    private static final String DEFAULT_ACTIVE = "false";
    private static final String ROLE_PARAM = "role";
    private static final String TENANT_HEADER = "X-Tenant";
    private static final String SORT_PARAM = "sort";
    private static final String DEFAULT_SORT = "created";

    @QueryParam(ACTIVE_PARAM)
    @DefaultValue(DEFAULT_ACTIVE)
    private Boolean active;

    @QueryParam(ROLE_PARAM)
    private String role;

    @HeaderParam(TENANT_HEADER)
    private String tenant;

    private String sort;

    public Boolean getActive() { return active; }
    public void setActive(Boolean active) { this.active = active; }

    public String getRole() { return role; }
    public void setRole(String role) { this.role = role; }

    public String getTenant() { return tenant; }
    public void setTenant(String tenant) { this.tenant = tenant; }

    public String getSort() { return sort; }

    @QueryParam(SORT_PARAM)
    @DefaultValue(DEFAULT_SORT)
    public void setSort(String sort) { this.sort = sort; }
}
