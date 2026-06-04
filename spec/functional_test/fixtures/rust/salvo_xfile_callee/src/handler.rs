use salvo::prelude::*;

#[handler]
pub async fn create_user(req: &mut Request, res: &mut Response) {
    let body = req.parse_json::<UserReq>().await.unwrap();
    let token = req.header::<&str>("Authorization").unwrap_or_default();
    UserService::insert(&body, token);
    res.render(Json(body));
}
