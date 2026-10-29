package com.example.dto;

import jakarta.ws.rs.*;

public class ItemSearch {
    @QueryParam("page") public Integer page;
    @HeaderParam("X-Tenant") public String tenant;
}
