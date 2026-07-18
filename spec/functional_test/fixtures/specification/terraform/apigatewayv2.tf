resource "aws_apigatewayv2_api" "http" {
  name          = "example-http"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_route" "list_items" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /items"
}

resource "aws_apigatewayv2_route" "create_item" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /items"
}

resource "aws_apigatewayv2_route" "get_item" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /items/{id}"
}

# WebSocket / catch-all keys carry no HTTP path and must be ignored.
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "$default"
}
