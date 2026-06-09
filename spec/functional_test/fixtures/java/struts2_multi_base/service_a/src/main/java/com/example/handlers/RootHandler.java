package com.example.handlers;

public class RootHandler {
    private final RootService aService = new RootService();

    public String execute() {
        aService.load();
        return "success";
    }
}
