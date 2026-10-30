package demo

import com.fasterxml.jackson.annotation.JsonRootName
import org.springframework.web.bind.annotation.*

@JsonRootName("user")
data class LoginParam(val email: String, val password: String)

data class NewArticleParam(val title: String)

@RestController
class UsersApi {
    @PostMapping("/users/login")
    fun login(@RequestBody param: LoginParam): String = "ok"

    @PostMapping("/articles")
    fun article(@RequestBody param: NewArticleParam): String = "ok"
}
