// A collector re-exported through a *nested* `use` group: the alias path is
// relative to the inner group (`build_routes`, not `events::build_routes`),
// so the mount must resolve it as a module-qualified suffix to apply /events.
#[macro_use]
extern crate rocket;

mod events;

use crate::{
    events::{build_routes as events_routes},
};

#[launch]
fn rocket() -> _ {
    rocket::build().mount("/events", events_routes())
}
