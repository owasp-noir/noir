require "../../func_spec.cr"

# FlaskBB's `register_view(bp, routes=[...], view_func=View.as_view(...))`
# helper: each route is an `add_url_rule` on `bp`, so a MethodView serves
# the verbs it defines and a function view the call's `methods=`. The
# blueprint is built inside the function that registers it, under
# `url_prefix=app.config["X"]`, read from the class `from_object` names
# (not a subclass's override, nor a same-named module constant
# elsewhere), with an `os.environ.get` default; a key only sibling
# classes set gives one row per value. A helper whose definition never
# calls `add_url_rule`, rewrites the rule or registers conditionally, a
# built `routes=` list, an unread helper handed no `view_func=`, and the
# `as_view` endpoint name give no row.
FunctionalTester.new("fixtures/python/flask_register_view/", {
  :techs     => 1,
  :endpoints => 12,
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
  Endpoint.new("/message/inbox", "GET"),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/dev-api/status", "GET"),
]).perform_tests
