// Rocket's generic `#[route(...)]` attribute (legacy verb-first and
// modern method-kwarg forms). Custom non-HTTP methods are skipped.
#[macro_use]
extern crate rocket;

#[route(GET, uri = "/legacy")]
fn legacy() -> &'static str { "ok" }

#[route("/modern", method = POST)]
fn modern() -> &'static str { "ok" }

#[route("/with-data", method = PUT, data = "<body>")]
fn with_data(body: String) -> String { body }

// Custom WebDAV method: not a standard HTTP verb -> not emitted.
#[route("/dav", method = PROPFIND)]
fn dav() -> &'static str { "ok" }

#[get("/plain")]
fn plain() -> &'static str { "ok" }
