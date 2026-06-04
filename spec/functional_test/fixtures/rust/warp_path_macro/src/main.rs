// warp's `path!` macro (the idiomatic multi-segment form) plus
// filter-returning helper functions whose tail expression IS the route.
use warp::Filter;

async fn list_todos() {}
async fn create_todo() {}
async fn update_todo() {}

// let-bound routes using path! with literal + typed segments.
fn build() {
    let _hello = warp::path!("hello" / "from" / "warp").map(|| "hi");
    let _sum = warp::path!("sum" / u32 / u32).and(warp::get()).map(|a, b| a + b);
}

// filter-returning helper functions (tail expression is the route).
pub fn todos_list() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    warp::path!("todos")
        .and(warp::get())
        .and_then(list_todos)
}

pub fn todos_create() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    warp::path!("todos")
        .and(warp::post())
        .and_then(create_todo)
}

pub fn todos_update() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    warp::path!("todos" / u64)
        .and(warp::put())
        .and_then(update_todo)
}

// A non-route helper filter: no path -> must NOT become an endpoint.
fn with_auth() -> impl Filter<Extract = (), Error = warp::Rejection> + Clone {
    warp::header::exact("authorization", "Bearer x")
}

fn main() {}
