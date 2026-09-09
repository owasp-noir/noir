require "../../func_spec.cr"

# `option (google.api.http).<field> = <value>;` — protobuf's generic
# "one field per statement" spelling of the same annotation the brace form
# writes in one block. Argo CD writes 70 of its 109 annotations this way, and
# noir used to read none of them.
expected_endpoints = [
  # A single statement carrying the whole route. GET has no body, so the
  # non-path message fields become query params.
  Endpoint.new("/v1/widgets/{widget_id}", "GET", [
    Param.new("widget_id", "", "path"),
    Param.new("name", "", "query"),
    Param.new("note", "", "query"),
  ]),
  # Verb + body + two repeated additional_bindings statements assembled into
  # one rule: the primary PUT and both PATCH bindings.
  Endpoint.new("/v1/widgets/{widget_id}", "PUT", [
    Param.new("widget_id", "", "path"),
    Param.new("name", "", "json"),
    Param.new("note", "", "json"),
  ]),
  Endpoint.new("/v1/widgets/{widget_id}", "PATCH", [
    Param.new("widget_id", "", "path"),
    Param.new("name", "", "json"),
    Param.new("note", "", "json"),
  ]),
  Endpoint.new("/v2/widgets/{widget_id}", "PATCH", [
    Param.new("widget_id", "", "path"),
    Param.new("name", "", "json"),
    Param.new("note", "", "json"),
  ]),
  # `.custom.kind` / `.custom.path`: the CustomHttpPattern spelled as two
  # separate field statements.
  Endpoint.new("/v1/widgets/{widget_id}/inspect", "OPTIONS", [
    Param.new("widget_id", "", "path"),
    Param.new("name", "", "json"),
    Param.new("note", "", "json"),
  ]),
  # `.body = "name"` names one field as the body; the rest go to the query.
  Endpoint.new("/v1/widgets/{widget_id}/rename", "POST", [
    Param.new("widget_id", "", "path"),
    Param.new("name", "", "json"),
    Param.new("note", "", "query"),
  ]),
  # An rpc with no annotation is still a pure gRPC endpoint.
  Endpoint.new("/field.v1.WidgetService/WatchWidget", "POST", [
    Param.new("widget_id", "", "json"),
    Param.new("name", "", "json"),
    Param.new("note", "", "json"),
  ]),
  # mixed_form.proto — brace form and field form in one file.
  Endpoint.new("/v1/gadgets/{gadget_id}", "GET", [
    Param.new("gadget_id", "", "path"),
    Param.new("label", "", "query"),
  ]),
  Endpoint.new("/v1/gadgets", "GET", [
    Param.new("gadget_id", "", "query"),
    Param.new("label", "", "query"),
  ]),
  # ...and both spellings on one rpc: each is read independently, so neither
  # route is dropped.
  Endpoint.new("/v1/gadgets/{gadget_id}", "PUT", [
    Param.new("gadget_id", "", "path"),
    Param.new("label", "", "json"),
  ]),
  Endpoint.new("/v1/gadgets/{gadget_id}/replace", "POST", [
    Param.new("gadget_id", "", "path"),
    Param.new("label", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/grpc_field_form/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
