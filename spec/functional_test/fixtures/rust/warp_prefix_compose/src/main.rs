use warp::Filter;

async fn list() -> Result<impl warp::Reply, warp::Rejection> { Ok("ok") }
async fn create() -> Result<impl warp::Reply, warp::Rejection> { Ok("ok") }

fn todos_list() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    warp::path!("todos").and(warp::get()).and_then(list)
}

fn todos_create() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    warp::path!("todos").and(warp::post()).and_then(create)
}

// Composes the per-route fns without a path of its own (warp's examples/todos.rs).
fn todos() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    todos_list().or(todos_create())
}

#[tokio::main]
async fn main() {
    // An inline prefix over let-bound alternatives (warp's examples/routing.rs).
    let users = warp::path("users").and(warp::get()).map(|| "users");
    let posts = warp::path("posts").and(warp::post()).map(|| "posts");
    let api = warp::path("api").and(users.or(posts));

    // An inline prefix over inline alternatives.
    let v2 = warp::path("v2").and(
        warp::path("items").and(warp::get()).map(|| "items")
            .or(warp::path("tags").and(warp::delete()).map(|| "tags")),
    );

    let svc = warp::path("svc").and(todos());

    warp::serve(api.or(v2).or(svc)).run(([127, 0, 0, 1], 3030)).await;
}
