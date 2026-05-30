package v1.post

import javax.inject.Inject

import play.api.routing.Router.Routes
import play.api.routing.SimpleRouter
import play.api.routing.sird._

// Programmatic SIRD router mounted from conf/routes via `-> /v1/posts ...`.
class PostRouter @Inject() (controller: PostController) extends SimpleRouter {
  val prefix = "/v1/posts"

  override def routes: Routes = {
    case GET(p"/") =>
      controller.index

    case POST(p"/") =>
      controller.process

    case GET(p"/$id") =>
      controller.show(id)

    case PUT(p"/$id<[0-9]+>") =>
      controller.update(id)
  }
}
