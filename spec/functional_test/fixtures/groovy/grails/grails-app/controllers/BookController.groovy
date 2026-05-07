package demo

class BookController {
    static allowedMethods = [
        save: 'POST',
        update: ['PUT', 'PATCH'],
        delete: 'DELETE'
    ]

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
