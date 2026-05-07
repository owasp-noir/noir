package demo

class BookController {
    static allowedMethods = [
        save: 'POST',
        update: ['PUT', 'PATCH'],
        delete: 'DELETE'
    ]

    // Field-style declarations and dependency-injected services share the
    // `def name = ...` syntax with closure-style actions; only the latter
    // should be surfaced as endpoints.
    def cache = [:]
    def messages = ['hi', 'bye']
    def bookService = new BookService()

    def index() {
        render 'list of books'
    }

    def show(Long id) {
        render "book ${id}"
    }

    def save() {
        render status: 201
    }

    def update(Long id) {
        render status: 200
    }

    def delete(Long id) {
        render status: 204
    }

    private def helper() {
        // Should not be exposed.
    }
}
