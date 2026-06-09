use salvo::prelude::*;

#[handler]
pub async fn submit(req: &mut Request) {
    let body = req.parse_json::<UserPayload>().await.unwrap();
    let token = req.header::<&str>("X-Service-B").unwrap_or_default();
    let _ = (body, token);
}
