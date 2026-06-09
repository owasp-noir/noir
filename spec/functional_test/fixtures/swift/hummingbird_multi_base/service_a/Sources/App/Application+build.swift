import Hummingbird

func buildApplication() -> some ApplicationProtocol {
    let router = Router()
    TodoController().addRoutes(to: router.group("a"))
    return Application(router: router)
}
