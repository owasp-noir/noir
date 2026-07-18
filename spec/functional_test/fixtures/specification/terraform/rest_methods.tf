# Methods live in a separate file from the resources they reference, exercising
# Terraform's module-wide (per-directory) graph resolution.
resource "aws_api_gateway_method" "list_users" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "get_user" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.user_id.id
  http_method   = "GET"
  authorization = "NONE"
}
