package com.example.entities;

import com.fasterxml.jackson.annotation.JsonUnwrapped;

public class Profile {
    public String name;

    @JsonUnwrapped(prefix = "home_")
    public Address home;
}
