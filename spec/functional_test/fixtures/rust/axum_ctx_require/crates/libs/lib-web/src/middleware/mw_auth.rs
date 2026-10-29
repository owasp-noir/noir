use crate::error::{Error, Result};
use axum::body::Body;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use axum::http::Request;
use axum::middleware::Next;
use axum::response::Response;

// Refuses through `ctx?`: `Error::CtxExt` maps to 403 in error.rs.
pub async fn mw_ctx_require(ctx: Result<CtxW>, req: Request<Body>, next: Next) -> Result<Response> {
    debug!("mw_ctx_require - {ctx:?}");
    ctx?;
    Ok(next.run(req).await)
}

// Control: `?` on an error that maps to 500.
pub async fn mw_ctx_loose(ctx: Result<CtxLoose>, req: Request<Body>, next: Next) -> Result<Response> {
    ctx?;
    Ok(next.run(req).await)
}

// Control: `?` on a body check that maps to 400.
pub async fn mw_body_check(body: Result<ParsedBody>, req: Request<Body>, next: Next) -> Result<Response> {
    body?;
    Ok(next.run(req).await)
}

// Control: only logs.
pub async fn mw_log(req: Request<Body>, next: Next) -> Response {
    debug!("mw_log - {}", req.uri());
    next.run(req).await
}

// Control: reads the ctx, never refuses.
pub async fn mw_ctx_peek(ctx: Result<CtxW>, req: Request<Body>, next: Next) -> Response {
    let _user = ctx.ok();
    next.run(req).await
}

#[derive(Debug, Clone)]
pub struct CtxW(pub u64);

impl<S: Send + Sync> FromRequestParts<S> for CtxW {
    type Rejection = Error;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self> {
        parts
            .extensions
            .get::<u64>()
            .map(|id| CtxW(*id))
            .ok_or(Error::CtxExt("ctx not in request ext".to_string()))
    }
}

#[derive(Debug, Clone)]
pub struct CtxLoose(pub u64);

impl<S: Send + Sync> FromRequestParts<S> for CtxLoose {
    type Rejection = Error;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self> {
        parts
            .extensions
            .get::<u64>()
            .map(|id| CtxLoose(*id))
            .ok_or(Error::CtxLoose("no ctx".to_string()))
    }
}

#[derive(Debug, Clone)]
pub struct ParsedBody(pub String);

impl<S: Send + Sync> FromRequestParts<S> for ParsedBody {
    type Rejection = Error;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self> {
        parts
            .headers
            .get("content-type")
            .map(|v| ParsedBody(format!("{v:?}")))
            .ok_or(Error::BadBody("no content type".to_string()))
    }
}
