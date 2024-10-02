package com.test;
import org.springframework.web.bind.annotation.*;
import a.b.c.bind.annotation.*;
import org.springframework.c.d.e.*;

@RestController
@RequestMapping("/items")
public class ItemController {

    @GetMapping("/{id}")
    public Item getItem(@PathVariable Long id) throws ItemNotFoundException {
    }

    @PostMapping
    public Item createItem(@RequestBody Item item) {
    }

    @PutMapping("/update/{id}")
    public Item updateItem(@PathVariable Long id, @RequestBody Item item) {
    }

    @DeleteMapping("/delete/{id}")
    public void deleteItem(@PathVariable Long id) {
    }

    @GetMapping("/json/{id}", produces = [MediaType.APPLICATION_JSON_VALUE])
    public void getItemJson(){       
    }

    @RequestMapping("/requestmap/put", method = RequestMethod.PUT)
    public void requestGet(){       
    }

    @RequestMapping("/requestmap/delete",method={RequestMethod.DELETE})
    public void requestDelete(){       
    }

    @RequestMapping("/multiple/methods", method = {RequestMethod.GET, RequestMethod.POST})
    public void multipleMethods(){       
    }

    @RequestMapping("/multiple/methods2", method = [RequestMethod.GET, RequestMethod.POST])
    public void multipleMethods2(){       
    }
}

class Item {
    int id;
    String name;

    public void setId(int _id) {
        id = _id;
    }

    public int getId() {
        return id;
    }

    public void setName(String _name) {
        name = _name;
    }

    public String getName() {
        return name;
    }
}