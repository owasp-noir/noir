use salvo::prelude::*;

#[handler]
async fn list_users(req: &mut Request, res: &mut Response) {
    let page = req.query::<u32>("page").unwrap_or(1);
    res.render(Text::Plain("users"));
}

#[handler]
async fn show_user(req: &mut Request, res: &mut Response) {
    let id = req.param::<i64>("id").unwrap();
    let token = req.header::<String>("authorization");
    res.render(Text::Plain("user"));
}

#[handler]
async fn create_user(req: &mut Request, res: &mut Response) {
    let name = req.form::<String>("name").await;
    res.render(Text::Plain("created"));
}

#[handler]
async fn hello() -> &'static str { "hi" }

#[tokio::main]
async fn main() {
    let router = Router::new()
        .get(hello)
        .push(
            Router::with_path("api/users")
                .get(list_users)
                .post(create_user)
                .push(Router::with_path("<id>").get(show_user).delete(show_user)),
        )
        .push(Router::with_path("files/<**rest>").get(hello))
        .push(Router::with_path("posts/<id:num>").get(hello));
    let acceptor = TcpListener::new("0.0.0.0:5800").bind().await;
    Server::new(acceptor).serve(router).await;
}
