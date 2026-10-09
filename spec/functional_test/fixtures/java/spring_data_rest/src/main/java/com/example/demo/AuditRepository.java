package com.example.demo;

import org.springframework.data.repository.CrudRepository;

// Package-private and unannotated: not exported.
interface AuditRepository extends CrudRepository<Person, Long> {
}
