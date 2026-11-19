use poem::{get, handler, Route};

#[handler]
fn panel() -> String { "panel".into() }

pub fn routes() -> Route {
    Route::new().at("/panel", get(panel))
}
