package demo

class AuthorController {
    // Legacy closure-style action.
    def list = {
        [authors: []]
    }

    def profile() {
        render 'author profile'
    }
}
