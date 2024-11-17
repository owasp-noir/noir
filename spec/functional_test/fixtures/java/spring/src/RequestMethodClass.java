package com.test;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RequestMapping(value = "/empty") // Comment

public class RequestMethodClass {
	
	@GetMapping("")
	public void getData() {
	}
}