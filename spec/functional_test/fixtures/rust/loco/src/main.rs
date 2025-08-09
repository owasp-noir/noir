use loco_rs::prelude::*;
use axum::{extract::Request, response::Response};

// Example Loco controller with typical patterns
pub struct HomeController;

impl HomeController {
    pub async fn index(req: Request) -> Result<Response> {
        // Home page handler
        Ok(Response::new("Welcome to Loco!"))
    }

    pub async fn about(req: Request) -> Result<Response> {
        // About page handler
        Ok(Response::new("About us"))
    }
}

pub struct ApiController;

impl ApiController {
    pub async fn users(req: Request) -> Result<Response> {
        // API users endpoint
        Ok(Response::new("Users API"))
    }

    pub async fn create_user(req: Request) -> Result<Response> {
        // Create user endpoint
        Ok(Response::new("User created"))
    }
}

// Function-style handlers
pub async fn health_check(req: Request) -> Result<Response> {
    Ok(Response::new("OK"))
}

pub async fn dashboard(req: Request) -> Result<Response> {
    Ok(Response::new("Dashboard"))
}