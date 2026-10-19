package com.test;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.WebDataBinder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.InitBinder;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
@RequestMapping("/binder")
public class BinderController {
    // spring-petclinic shape: a submitted `id` is never bound.
    @InitBinder
    public void setAllowedFields(WebDataBinder dataBinder) {
        dataBinder.setDisallowedFields("id", "*.id");
    }

    @PostMapping("/pets")
    public String create(Pet pet) {
        return "ok";
    }

    // An explicit request parameter is not data binding: `id` stays.
    @GetMapping("/lookup")
    public String lookup(@RequestParam("id") String id) {
        return id;
    }
}

class Pet {
    public String id;
    public String name;
    public String secret;
    public Owner owner;
}

class Owner {
    public String id;
    public String city;
}
