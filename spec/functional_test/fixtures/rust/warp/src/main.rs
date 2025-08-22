use warp::Filter;

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

    // GET /users/123
    let get_user = warp::path("users")
        .and(warp::path::param::<u32>())
        .and(warp::path::end())
        .and(warp::get())
        .map(|id: u32| format!("User ID: {}", id));

    // POST /users
    let create_user = warp::path("users")
        .and(warp::path::end())
        .and(warp::post())
        .map(|| "User created");

    let routes = hello
        .or(hello_path)
        .or(get_user)
        .or(create_user);

    warp::serve(routes)
        .run(([127, 0, 0, 1], 3030))
        .await;
}