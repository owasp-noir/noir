use serde::Deserialize;
use std::collections::HashMap;
use warp::Filter;

#[derive(Deserialize)]
struct ListOptions {
    offset: Option<usize>,
    limit: Option<usize>,
}

#[tokio::main]
async fn main() {
    let api = warp::path("api").and(warp::path("v1"));

    let list = warp::path!("todos")
        .and(warp::get())
        .and(warp::query::<ListOptions>())
        .map(|_opts: ListOptions| "list");

    let create = warp::path!("todos")
        .and(warp::post())
        .and(warp::body::json())
        .and(warp::header::<String>("authorization"))
        .map(|_b: HashMap<String, String>, _a: String| "create");

    let update = warp::path!("todos" / u64)
        .and(warp::put())
        .and(warp::body::form())
        .map(|_id, _f: HashMap<String, String>| "update");

    let delete = warp::path!("todos" / u64)
        .and(warp::delete())
        .and(warp::cookie::<String>("session"))
        .map(|_id, _c: String| "delete");

    let routes = api.and(list.or(create).or(update).or(delete));
    let hello = warp::path!("hello" / String).map(|name| format!("Hello, {}!", name));

    warp::serve(routes.or(hello)).run(([127, 0, 0, 1], 3030)).await;
}
