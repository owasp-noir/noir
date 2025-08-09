use loco_rs::prelude::*;
use axum::{extract::State, response::Response};
use serde_json::Json;

// Example Loco controller following Rails conventions
pub struct PostsController;

impl PostsController {
    // RESTful actions following Rails conventions
    pub async fn index(State(ctx): State<AppContext>) -> Result<impl IntoResponse> {
        // List all posts
        Ok(Html("Posts index"))
    }

    pub async fn show(State(ctx): State<AppContext>) -> Result<impl IntoResponse> {
        // Show specific post
        Ok(Html("Post details"))
    }

    pub async fn new(State(ctx): State<AppContext>) -> Result<impl IntoResponse> {
        // New post form
        Ok(Html("New post form"))
    }

    pub async fn create(State(ctx): State<AppContext>) -> Result<impl IntoResponse> {
        // Create post
        Ok(Json("Post created"))
    }

    pub async fn edit(State(ctx): State<AppContext>) -> Result<impl IntoResponse> {
        // Edit post form
        Ok(Html("Edit post form"))
    }

    pub async fn update(State(ctx): State<AppContext>) -> Result<impl IntoResponse> {
        // Update post
        Ok(Json("Post updated"))
    }

    pub async fn destroy(State(ctx): State<AppContext>) -> Result<impl IntoResponse> {
        // Delete post
        Ok(Json("Post deleted"))
    }
}

// API controller
pub struct ApiController;

impl ApiController {
    pub async fn users(State(ctx): State<AppContext>) -> Result<Json<Value>> {
        // API users endpoint
        Ok(Json("Users API"))
    }

    pub async fn health_check(State(ctx): State<AppContext>) -> Result<Json<Value>> {
        // Health check endpoint
        Ok(Json("OK"))
    }
}

// Function-style handlers
pub async fn dashboard(State(ctx): State<AppContext>) -> Result<impl IntoResponse> {
    Ok(Html("Dashboard"))
}