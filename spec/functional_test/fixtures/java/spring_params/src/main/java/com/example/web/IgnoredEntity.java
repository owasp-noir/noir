package com.example.web;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonSetter;

public class IgnoredEntity {
    @JsonIgnore
    private String searchValue;
    private String hidden;
    private String secret;
    private String name;

    public void setSearchValue(String searchValue) { this.searchValue = searchValue; }

    @JsonIgnore
    public String getHidden() { return hidden; }
    public void setHidden(String hidden) { this.hidden = hidden; }

    @JsonIgnore
    public String getSecret() { return secret; }
    @JsonProperty
    public void setSecret(String secret) { this.secret = secret; }

    public void setName(String name) { this.name = name; }

    @JsonIgnore
    private byte[] blob;

    @JsonSetter("blob")
    public void setBlobBase64(String value) { this.blob = value.getBytes(); }
}
