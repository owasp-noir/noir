package com.test;
import org.springframework.web.bind.annotation.*;
import a.b.c.bind.annotation.*;
import org.springframework.c.d.e.*;

@RestController
@RequestMapping("items2")
public class ItemController {

    @GetMapping("{id}")
    public Item getItem(@PathVariable Long id) throws ItemNotFoundException {
    }

    @PostMapping(
        "/create" /* comment */
    )
    public Item createItem(@RequestBody Item item) {
    }

    @PutMapping
    (
        "edit/"
    ) /* comment */
    public Item editItem(@RequestBody Item item) {
    }

    @GetMapping(value = "/{id}/thePath")
    @Dummy
    (
        "test"
    ) //comment
    @Operation( //comment
        summary = "Some summary",
        tags = {"example"},
      responses = {@ApiResponse(content = @Content(schema = @Schema(implementation = Authorization.class)))}
    ) //comment
    public ResponseEntity<Object> someMethod(@PathVariable String id) throws SomeException {
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
