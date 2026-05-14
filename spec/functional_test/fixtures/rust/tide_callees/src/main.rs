use serde::Deserialize;
use tide::{Request, Result};

#[derive(Debug, Deserialize)]
struct SearchQuery {
    q: String,
}

#[derive(Debug, Deserialize)]
struct UserData {
    name: String,
}

#[async_std::main]
async fn main() -> Result<()> {
    let mut app = tide::new();

    app.at("/").get(home);
    app.at("/users/:id").get(get_user);
    app.at("/api/users").post(create_user);

    let account_route = app.at("/accounts/:id");
    account_route.put(update_account);

    app.at("/auth").get(auth_handler);
    app.at("/complex/:id").post(complex_handler);

    app.listen("127.0.0.1:8080").await?;
    Ok(())
}

async fn home(_req: Request<()>) -> Result {
    let status = HealthCheck::ready();
    Ok(render_home(status).into())
}

async fn get_user(req: Request<()>) -> Result {
    let id = req.param("id")?;
    let user = UserService::load(id);
    AuditLog::read_user();
    Ok(UserPresenter::render(user).into())
}

async fn create_user(mut req: Request<()>) -> Result {
    let user: UserData = req.body_json().await?;
    let created = UserService::create(user);
    Ok(UserPresenter::render(created).into())
}

async fn update_account(req: Request<()>) -> Result {
    let query: SearchQuery = req.query()?;
    let account = AccountService::update(query);
    Ok(AccountPresenter::render(account).into())
}

async fn auth_handler(req: Request<()>) -> Result {
    let token = req.header("Authorization");
    let session = req.cookie("session_id");
    AuthService::validate(token, session);
    Ok("authenticated".into())
}

async fn complex_handler(mut req: Request<()>) -> Result {
    let id = req.param("id")?;
    let query: SearchQuery = req.query()?;
    let user: UserData = req.body_json().await?;
    let token = req.header("Authorization");
    let session = req.cookie("session_id");
    ComplexService::process(id, query, user, token, session);
    Ok("complex".into())
}

/*
async fn complex_handler(mut req: Request<()>) -> Result {
    let shadow: ShadowPayload = req.body_json().await?;
    ShadowService::hidden(shadow);
    Ok("shadow".into())
}
*/
