use loco_rs::{app::{AppContext, Hooks}, controller::AppRoutes};
use crate::controllers;

pub struct App;

impl Hooks for App {
    fn routes(_ctx: &AppContext) -> AppRoutes {
        // `prefix` applies to the controllers added after it.
        AppRoutes::with_default_routes()
            .add_route(controllers::health::routes())
            .prefix("/l-api")
            .add_route(controllers::auth::routes())
    }
}
