package com.acme.web

import org.springframework.core.annotation.AliasFor
import org.springframework.web.bind.annotation.*

@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
@RestController
@RequestMapping("/meta-api")
annotation class ApiController

@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
@RequestMapping(method = [RequestMethod.GET], path = ["/audit"])
annotation class AuditGet
