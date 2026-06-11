use serde::Deserialize;
use warp::{Filter, Rejection, Reply};

#[derive(Deserialize)]
struct SearchQuery {
    q: String,
}

#[derive(Deserialize)]
struct CreateUser {
    username: String,
}

fn home_handler() -> impl Reply {
    let status = HealthCheck::ready();
    render_home(status)
}

async fn get_user(id: u32) -> Result<impl Reply, Rejection> {
    let user = UserService::load(id);
    AuditLog::read_user();
    Ok(UserPresenter::render(user))
}

async fn create_user(user: CreateUser) -> Result<impl Reply, Rejection> {
    let created = UserService::create(user);
    AuditLog::write();
    Ok(UserPresenter::render(created))
}

async fn profile_handler(query: SearchQuery) -> impl Reply {
    let profile = ProfileService::search(query);
    ProfilePresenter::render(profile)
}

pub unsafe fn generic_handler<T>() -> impl Reply {
    let value = GenericService::load();
    GenericPresenter::render(value)
}

mod external;

#[tokio::main]
async fn main() {
    let home = warp::path::end()
        .and(warp::get())
        .map(home_handler);

    let get_user_route = warp::path("users")
        .and(warp::path::param::<u32>())
        .and(warp::path::end())
        .and(warp::get())
        .and_then(get_user);

    let create_user_route = warp::path("users")
        .and(warp::path::end())
        .and(warp::body::json::<CreateUser>())
        .and(warp::post())
        .and_then(create_user);

    let external_route = warp::path("external")
        .and(warp::path::end())
        .and(warp::body::json::<CreateUser>())
        .and(warp::post())
        .and_then(external::create_external);

    let profile_route = warp::path("profile")
        .and(warp::path::end())
        .and(warp::query::<SearchQuery>())
        .and(warp::get())
        .then(profile_handler);

    let generic_route = warp::path("generic")
        .and(warp::path::end())
        .and(warp::get())
        .map(handlers::generic_handler::<u32>);

    let routes = home
        .or(get_user_route)
        .or(create_user_route)
        .or(external_route)
        .or(profile_route)
        .or(generic_route);

    warp::serve(routes)
        .run(([127, 0, 0, 1], 3030))
        .await;
}
