package com.example.entities;

import com.fasterxml.jackson.annotation.JsonProperty;

public record SessionUpdate(@JsonProperty("push_token") String pushToken, String captcha) {
}
