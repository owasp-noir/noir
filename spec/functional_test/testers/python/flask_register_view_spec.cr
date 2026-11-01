require "../../func_spec.cr"

# FlaskBB's `register_view(bp, routes=[...], view_func=View.as_view(...))`
# helper: each route is an `add_url_rule` on `bp`, so a MethodView serves
# the verbs it defines and a function view the call's `methods=`. The
# blueprint is built inside the function that registers it, under
# `url_prefix=app.config["X"]`, read from the config class (not from a
# same-named module constant elsewhere). A helper whose definition never
# calls `add_url_rule` registers nothing, and the `as_view` endpoint name
# is no URL.
FunctionalTester.new("fixtures/python/flask_register_view/", {
  :techs     => 1,
  :endpoints => 9,
}, [
  Endpoint.new("/user/topic/<int:topic_id>", "GET", [Param.new("topic_id", "", "path")]),
  Endpoint.new("/user/topic/<int:topic_id>", "POST", [Param.new("topic_id", "", "path")]),
  Endpoint.new("/user/topic/<int:topic_id>-<slug>", "GET"),
  Endpoint.new("/user/topic/<int:topic_id>-<slug>", "POST"),
  Endpoint.new("/user/login", "GET"),
  Endpoint.new("/user/login", "POST"),
  Endpoint.new("/user/post/<int:post_id>/raw", "GET"),
  Endpoint.new("/user/post/<int:post_id>/raw", "POST"),
  Endpoint.new("/admin/", "GET"),
]).perform_tests
