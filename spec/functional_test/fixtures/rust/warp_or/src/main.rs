use warp::Filter;

// Inline `.or(..)` alternatives are separate routes; they must not merge
// into one endpoint that concatenates every branch's path.
#[tokio::main]
async fn main() {
    let routes = warp::path("hello")
        .and(warp::get())
        .map(|| "hi")
        .or(warp::path("bye").and(warp::post()).map(|| "bye"));
    warp::serve(routes).run(([127, 0, 0, 1], 3030)).await;
}

fn api() -> impl Filter<Extract = impl warp::Reply, Error = warp::Rejection> + Clone {
    warp::path("a")
        .and(warp::put())
        .map(|| "a")
        .or(warp::path("b").and(warp::delete()).map(|| "b").or(warp::path("c").map(|| "c")))
        .recover(handle_rejection)
}
