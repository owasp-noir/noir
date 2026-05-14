package demo

class AuthorController {
    def authorService

    def list = {
        def authors = authorService.list(params)
        render authors
    }

    String profile() {
        def profile = profileService.show(params.id)
        render profile
    }
}
