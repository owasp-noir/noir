#[macro_use] extern crate rocket;

use rocket::serde::json::Json;
use rocket::form::Form;

#[get("/")]
fn index() -> &'static str {
    "Hello, world!"
}

#[post("/customer", data = "<input>")]
fn customer() -> &'static str {
    "Hello, world!"
}

// Path parameters
#[get("/users/<id>")]
fn get_user(id: i32) -> String {
    format!("User {}", id)
}

#[get("/posts/<category>/<id>")]
fn get_post(category: String, id: i32) -> String {
    format!("Post {} in {}", id, category)
}

// Query parameters
#[get("/search?<query>&<limit>")]
fn search(query: String, limit: Option<i32>) -> String {
    format!("Searching: {}", query)
}

#[get("/filter?<name>&<age>&<active>")]
fn filter(name: String, age: i32, active: bool) -> String {
    format!("Filter: {} {} {}", name, age, active)
}

// Body/Data parameters
#[post("/users", data = "<user>")]
fn create_user(user: String) -> String {
    "User created".to_string()
}

#[put("/products/<id>", data = "<product>")]
fn update_product(id: i32, product: String) -> String {
    format!("Product {} updated", id)
}

// Form data
#[post("/login", data = "<credentials>")]
fn login(credentials: String) -> String {
    "Login success".to_string()
}

// Mixed parameters
#[post("/items/<id>?<version>", data = "<item>")]
fn update_item(id: i32, version: Option<String>, item: String) -> String {
    format!("Item {} updated", id)
}

#[launch]
fn rocket() -> _ {
    rocket::build().mount("/", routes![
        index,
        customer,
        get_user, 
        get_post, 
        search,
        filter,
        create_user, 
        update_product,
        login,
        update_item
    ])
}