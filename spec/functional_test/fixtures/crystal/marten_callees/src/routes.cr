Marten.routes.draw do
  path "/", HomeHandler, name: "home"
  path "/api/users", UsersHandler, name: "users"
  path "/api/users/<int:id>", UserDetailHandler, name: "user_detail"
  path "/admin/reports", Admin::ReportsHandler, name: "admin_reports"
  path "/absolute/reports", ::Admin::ReportsHandler, name: "absolute_reports"
  path "/macro", MacroWrappedHandler, name: "macro"
end
