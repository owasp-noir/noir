import Hummingbird

func buildApplication() -> some ApplicationProtocol {
    let router = Router()
    TodoController().addRoutes(to: router.group("b"))
    return Application(router: router)
}
