package com.test;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class OwnerController {

    private final OwnerRepository owners;

    private final PetStore pets;

    private final NotificationService notifications;

    private final PaymentClient payments;

    public OwnerController(OwnerRepository owners, PetStore pets, NotificationService notifications, PaymentClient payments) {
        this.owners = owners;
        this.pets = pets;
        this.notifications = notifications;
        this.payments = payments;
    }

    // Runs before every handler, but looks the owner up only under {ownerId}.
    @ModelAttribute("owner")
    public Owner findOwner(@PathVariable(name = "ownerId", required = false) Integer ownerId) {
        return ownerId == null ? new Owner() : this.owners.findById(ownerId).orElseThrow();
    }

    @GetMapping("/owners/new")
    public String initCreationForm() {
        return "owners/form";
    }

    @GetMapping("/owners/{ownerId}")
    public String showOwner() {
        return "owners/details";
    }

    @PostMapping("/owners/new")
    public String processCreationForm(Owner owner) {
        this.owners.save(owner);
        return "redirect:/owners";
    }

    @GetMapping("/owners")
    public String listOwners(String lastName) {
        Page<Owner> page = findPage(lastName);
        return page.isEmpty() ? "owners/find" : "owners/list";
    }

    private Page<Owner> findPage(String lastName) {
        return owners.findByLastNameStartingWith(lastName, PageRequest.of(0, 5));
    }

    @GetMapping("/pets")
    public String listPets() {
        pets.findAll();
        return "pets/list";
    }

    @GetMapping("/pets/types")
    public String petTypes() {
        pets.petTypes();
        return "pets/types";
    }

    @PostMapping("/notify")
    public String notifyOwner(String message) {
        notifications.save(message);
        payments.findById(message);
        return "ok";
    }

    @GetMapping("/owners/kind")
    public String ownerKind() {
        return owners.getClass().getName();
    }
}
