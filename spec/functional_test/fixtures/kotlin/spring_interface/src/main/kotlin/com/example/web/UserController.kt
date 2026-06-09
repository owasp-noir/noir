package com.example.web

import com.example.api.UserApi
import com.example.api.UserCreate
import org.springframework.web.bind.annotation.RestController

@RestController
class UserController(private val service: UserService) : UserApi {
    override fun show(id: String): String {
        return service.show(id)
    }

    override fun create(user: UserCreate): String {
        return service.create(user.name, user.email)
    }
}

class UserService {
    fun show(id: String): String = id
    fun create(name: String, email: String): String = "$name:$email"
}
