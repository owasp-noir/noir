use poem::{get, Route};

mod admin;

pub fn routes() -> Route {
    Route::new()
        .at("/", get(index))
        .nest("/admin", admin::routes())
}

fn twice() -> Route {
    Route::new().at("/t", get(index))
}

fn top() -> Route {
    Route::new()
        .nest("/v1", twice())
        .nest("/v2", twice())
        .nest("/api", Route::new().at("/inline", get(index)).nest("/deep", Route::new().at("/d", get(index))))
        .at("/after", get(index))
}

async fn index() {}
