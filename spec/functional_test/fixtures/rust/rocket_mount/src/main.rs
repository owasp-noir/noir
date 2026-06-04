// Router setup. The `.mount()` calls live here; the handlers live in
// sibling modules. Exercises every cross-file mount shape:
//   * direct routes![] with module-qualified leaves   (/users)
//   * array-concat prefix [base, "/admin"].concat()    (/admin)
//   * mount(prefix, collector_fn()) + recursive append (/api)
#[macro_use]
extern crate rocket;

mod admin;
mod api;
mod users;

#[launch]
fn rocket() -> _ {
    let base = "";
    rocket::build()
        .mount("/users", routes![users::list, users::get_one])
        .mount([base, "/admin"].concat(), admin::routes())
        .mount("/api", api::all_routes())
}
