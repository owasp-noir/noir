import Hummingbird

struct TodoController<Context: RequestContext> {
    func addRoutes(to group: RouterGroup<Context>) {
        group.get("items") { _, _ in .ok }
    }
}
