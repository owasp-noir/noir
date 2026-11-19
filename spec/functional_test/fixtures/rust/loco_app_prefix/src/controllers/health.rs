use loco_rs::prelude::*;

async fn ping() -> Result<Response> { format::json(()) }

pub fn routes() -> Routes {
    Routes::new().prefix("/status").add("/ping", get(ping))
}
