use loco_rs::prelude::*;
use axum::{extract::{State, Path, Query}, response::Response, http::{Request, HeaderMap}};
use serde::{Deserialize, Serialize};
use serde_json::Json;

#[derive(Deserialize)]
struct SearchQuery {
    q: String,
    page: Option<u32>,
}

#[derive(Deserialize, Serialize)]
struct CreatePostData {
    title: String,
    content: String,
}

#[derive(Deserialize)]
struct LoginForm {
    username: String,
    password: String,
}

// Example Loco controller following Rails conventions
pub struct PostsController;

impl PostsController {
    // RESTful actions following Rails conventions
    pub async fn index(State(ctx): State<AppContext>, Query(params): Query<SearchQuery>) -> Result<impl IntoResponse> {
        // List all posts with query parameters
        Ok(Html("Posts index"))
    }

    pub async fn show(State(ctx): State<AppContext>, Path(id): Path<i32>) -> Result<impl IntoResponse> {
        // Show specific post with path parameter
        Ok(Html("Post details"))
    }

    pub async fn new(State(ctx): State<AppContext>) -> Result<impl IntoResponse> {
        // New post form
        Ok(Html("New post form"))
    }

    pub async fn create(State(ctx): State<AppContext>, Json(data): Json<CreatePostData>) -> Result<impl IntoResponse> {
        // Create post with JSON body
        Ok(Json("Post created"))
    }

    pub async fn edit(State(ctx): State<AppContext>, Path(id): Path<i32>) -> Result<impl IntoResponse> {
        // Edit post form with path parameter
        Ok(Html("Edit post form"))
    }

    pub async fn update(State(ctx): State<AppContext>, Path(id): Path<i32>, Json(data): Json<CreatePostData>) -> Result<impl IntoResponse> {
        // Update post with path parameter and JSON body
        Ok(Json("Post updated"))
    }

    pub async fn destroy(State(ctx): State<AppContext>, Path(id): Path<i32>) -> Result<impl IntoResponse> {
        // Delete post with path parameter
        Ok(Json("Post deleted"))
    }
}

// API controller
pub struct ApiController;

impl ApiController {
    pub async fn users(State(ctx): State<AppContext>, headers: HeaderMap) -> Result<Json<Value>> {
        // API users endpoint with header extraction
        let auth = headers.get("Authorization");
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

// Handler with form data
pub async fn login(State(ctx): State<AppContext>, Form(form): Form<LoginForm>) -> Result<impl IntoResponse> {
    Ok(Json("Logged in"))
}