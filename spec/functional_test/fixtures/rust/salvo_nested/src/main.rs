// Nested Router prefix composition through `.push(...)`, bare-root verbs,
// `.path()`-method chains, and a regex-constrained raw-string param.
use salvo::prelude::*;

#[handler]
async fn index() {}
#[handler]
async fn list_todos() {}
#[handler]
async fn create_todo() {}
#[handler]
async fn get_todo() {}
#[handler]
async fn delete_user() {}

fn route() -> Router {
    Router::new()
        // bare-root verb (no .path) registers at "/"
        .get(index)
        .push(
            Router::with_path("api").push(
                Router::with_path("todos")
                    .get(list_todos)
                    .post(create_todo)
                    .push(Router::with_path("{id}").get(get_todo)),
            ),
        )
        .push(
            Router::new()
                .path("user")
                .push(Router::new().path(r"delete/{id|[0-9a-fA-F]{8}}").post(delete_user)),
        )
}

fn main() {}
