package com.example.entities;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonUnwrapped;

// `update` has no key of its own: SessionUpdate's properties sit inline.
public record CreateSession(@JsonProperty String number, @JsonUnwrapped SessionUpdate update) {
}
