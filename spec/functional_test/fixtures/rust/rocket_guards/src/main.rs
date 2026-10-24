#[macro_use]
extern crate rocket;

mod guards;

use guards::{AuthUser, ClientInfo, OrgSession, Session};
use rocket::form::Form;
use rocket::serde::json::{Json, Value};
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LoginData {
    user_name: String,
    #[serde(rename = "pw")]
    password: String,
    #[serde(skip)]
    cache: Option<String>,
    r#type: i32,
}

#[derive(FromForm)]
struct Range {
    start: String,
    #[field(name = "continuationToken")]
    continuation_token: Option<String>,
}

#[get("/me")]
fn me(session: Session) -> String {
    session.user
}

/// Deletes an organization.
#[delete("/org/<id>")]
#[allow(unused_variables)]
fn delete_org(id: i32, _org: OrgSession) -> &'static str {
    "ok"
}

#[get("/client")]
fn client(_info: ClientInfo) -> &'static str {
    "ok"
}

#[get("/maybe")]
fn maybe(session: Option<Session>) -> &'static str {
    "ok"
}

#[get("/hint")]
fn hint(_hint: AuthUser) -> &'static str {
    "ok"
}

#[post("/login", data = "<data>")]
fn login(data: Json<LoginData>) -> &'static str {
    "ok"
}

#[post("/login-form", data = "<data>")]
fn login_form(data: Form<Range>) -> &'static str {
    "ok"
}

#[get("/events?<range..>")]
fn events(range: Range, _s: Session) -> &'static str {
    "ok"
}

#[post("/raw", data = "<raw>")]
fn raw(raw: Json<Value>) -> &'static str {
    "ok"
}

#[launch]
fn rocket() -> _ {
    rocket::build().mount(
        "/api",
        routes![me, delete_org, client, maybe, hint, login, login_form, events, raw],
    )
}
