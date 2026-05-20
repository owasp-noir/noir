package demo

// Controller using `void`-return actions, common in modern Grails
// codebases that pair `respond`/`render` calls with strict typing.
class ReportController {
    void index() {
        render 'reports index'
    }

    void show(Long id) {
        render "report ${id}"
    }
}
