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
}