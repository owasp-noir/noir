require "../../func_spec.cr"

list = Endpoint.new("/custom-trpc/user.list", "GET")
list.push_callee(Callee.new("UserService.list", line: 5))

create = Endpoint.new("/custom-trpc/user.create", "POST")
create.push_callee(Callee.new("AuditLog.write", line: 12))
create.push_callee(Callee.new("UserService.create", line: 13))

feed = Endpoint.new("/custom-trpc/post.liveFeed", "SUBSCRIBE")
feed.push_callee(Callee.new("FeedService.live", line: 10))

FunctionalTester.new("fixtures/typescript/trpc/", {
  :techs     => 1,
  :endpoints => 9,
}, [list, create, feed], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
