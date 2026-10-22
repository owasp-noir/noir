use poem::{get, Route};

pub fn routes() -> Route {
    Route::new().at("/panel", get(panel))
}

async fn panel() {}
