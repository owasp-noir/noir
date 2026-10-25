package com.example.entities;

import com.fasterxml.jackson.annotation.JsonUnwrapped;

// Unwraps into itself: the cyclic field contributes nothing.
public class Node {
    public String id;

    @JsonUnwrapped
    public Node next;
}
