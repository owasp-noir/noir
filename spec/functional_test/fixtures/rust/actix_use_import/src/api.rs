use actix_web::web;

use crate::handlers::health;

pub fn config(cfg: &mut web::ServiceConfig) {
    cfg.service(health);
}
