package com.example.dto;

import lombok.Data;

@Data
public class CreateItemRequest {
    private String name;
    private Integer price;
}
