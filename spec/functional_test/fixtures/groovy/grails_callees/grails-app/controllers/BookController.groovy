package demo

// Long comment before the controller keeps source offsets honest.
/*
 * Ignored.beforeController()
 */
class BookController {
    static allowedMethods = [
        save: 'POST',
        update: ['PUT', 'PATCH']
    ]

    def cache = [:]
    def bookService = new BookService()

    def index() {
        def books = bookService.list()
        AuditLog.write('book.index', books)
        def ignored = "Ignored.string()"
        render view: 'index', model: [books: books]
    }

    def save() {
        def book = bookService.save(request.JSON)
        respond book
    }

    def update(Long id) {
        def book = bookService.update(id, params)
        withTransaction {
            AuditLog.write 'book.update', book
        }
        redirect(action: 'show', id: id)
    }

    def show(Long id) {
        def ignoredSlashy = /Ignored.slashy(})/
        def ignoredDollar = $/Ignored.dollar({})/$
        def ignoredTriple = '''Ignored.triple({})'''
        return render view: 'show', model: [book: bookService?.find(id)]
    }

    private def helper() {
        Hidden.call()
    }
}
