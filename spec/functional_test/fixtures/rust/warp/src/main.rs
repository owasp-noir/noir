use warp::Filter;
use serde::Deserialize;

#[derive(Deserialize)]
struct SearchQuery {
    q: String,
    page: Option<u32>,
}

#[derive(Deserialize)]
struct CreateUser {
    username: String,
    email: String,
}

#[tokio::main]
async fn main() {
    // GET /
    let hello = warp::path::end()
        .and(warp::get())
        .map(|| "Hello, World!");

    // GET /hello
    let hello_path = warp::path("hello")
        .and(warp::path::end())
        .and(warp::get())
        .map(|| "Hello!");

    // GET /users/123 - Path parameter
    let get_user = warp::path("users")
        .and(warp::path::param::<u32>())
        .and(warp::path::end())
        .and(warp::get())
        .map(|id: u32| format!("User ID: {}", id));

    // GET /search?q=test&page=1 - Query parameters
    let search = warp::path("search")
        .and(warp::path::end())
        .and(warp::query::<SearchQuery>())
        .and(warp::get())
        .map(|query: SearchQuery| format!("Search: {}", query.q));

    // POST /users - JSON body
    let create_user = warp::path("users")
        .and(warp::path::end())
        .and(warp::body::json::<CreateUser>())
        .and(warp::post())
        .map(|user: CreateUser| format!("Created: {}", user.username));

    // GET /protected - Header parameter
    let protected = warp::path("protected")
        .and(warp::path::end())
        .and(warp::header::<String>("authorization"))
        .and(warp::get())
        .map(|auth: String| format!("Auth: {}", auth));

    // GET /session - Cookie parameter
    let session = warp::path("session")
        .and(warp::path::end())
        .and(warp::cookie::<String>("session_id"))
        .and(warp::get())
        .map(|session_id: String| format!("Session: {}", session_id));

    let routes = hello
        .or(hello_path)
        .or(get_user)
        .or(search)
        .or(create_user)
        .or(protected)
        .or(session);

    warp::serve(routes)
        .run(([127, 0, 0, 1], 3030))
        .await;
}