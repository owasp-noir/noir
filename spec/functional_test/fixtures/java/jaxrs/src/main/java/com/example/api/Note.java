package com.example.api;

import com.fasterxml.jackson.annotation.JsonProperty;

public class Note {
    public String title;
    public transient String excerpt;
    public transient int readCount;
    public transient String author;
    @JsonProperty public transient String color;

    public void setAuthor(String author) { this.author = author; }
}
