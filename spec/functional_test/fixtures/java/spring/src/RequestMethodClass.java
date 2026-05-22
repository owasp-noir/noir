package com.test;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RequestMapping(value = "/empty", params = "tenant") // Comment

public class RequestMethodClass {
	
	@GetMapping("")
	public void getData() {
	}

	@GetMapping(value = "/filtered", params = {"mode=full", "!skip"}, headers = {"X-Client=mobile", "!X-Debug"})
	public void getFiltered() {
	}
}
