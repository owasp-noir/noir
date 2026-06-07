use crate::{consts::PREFIX, handler};
use salvo::prelude::*;

pub fn build_shared_route() -> Router {
    Router::new()
        .path(PREFIX.to_owned() + "users")
        .post(handler::submit)
}
