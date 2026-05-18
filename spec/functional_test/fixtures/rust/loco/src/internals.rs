// Regression guard: a Rust source file that doesn't import
// `loco_rs::...` is framework infrastructure (or unrelated code),
// not a Loco user controller. The analyzer should ignore the
// `pub async fn` items below — none of these names should
// surface as endpoints in the fixture's expected-endpoints list.
use crate::db;

pub async fn run_task() {
    // framework helper, not a controller action
}

pub async fn start_scheduler() {
    // ditto
}
