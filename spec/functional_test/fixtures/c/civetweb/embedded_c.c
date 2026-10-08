/* CivetWeb C API (shape of civetweb/examples/embedded_c and examples/rest). */
#include <string.h>
#include "civetweb.h"

#define EXAMPLE_URI "/res/*/*"
#define EXIT_URI "/exit"

static int
ResourceGET(struct mg_connection *conn, const char *qs)
{
	char limit[16];
	mg_get_var(qs, strlen(qs), "limit", limit, sizeof(limit));
	return 200;
}

static int
ExampleHandler(struct mg_connection *conn, void *cbdata)
{
	const struct mg_request_info *ri = mg_get_request_info(conn);
	if (0 == strcmp(ri->request_method, "GET")) {
		return ResourceGET(conn, ri->query_string);
	}
	if ((0 == strcmp(ri->request_method, "PUT"))
	    || (0 == strcmp(ri->request_method, "POST"))) {
		const char *ct = mg_get_header(conn, "Content-Type");
		return 201;
	}
	if (0 == strcmp(ri->request_method, "DELETE")) {
		return 204;
	}
	return 405;
}

static int
ExitHandler(struct mg_connection *conn, void *cbdata)
{
	mg_printf(conn, "HTTP/1.1 200 OK\r\n\r\nBye!\n");
	return 1;
}

static int
CookieHandler(struct mg_connection *conn, void *cbdata)
{
	const char *cookie = mg_get_header(conn, "Cookie");
	char first[32];
	mg_get_cookie(cookie, "first", first, sizeof(first));
	return 1;
}

static int
FooHandler(struct mg_connection *conn, void *cbdata)
{
	return 1;
}

int
main(void)
{
	struct mg_context *ctx = mg_start(NULL, 0, NULL);
	mg_set_request_handler(ctx, EXAMPLE_URI, ExampleHandler, 0);
	mg_set_request_handler(ctx, EXIT_URI, ExitHandler, 0);
	mg_set_request_handler(ctx,
	                       "/cookie$",
	                       CookieHandler,
	                       (void *)0);
	/* Extension pattern, not a path: skipped. */
	mg_set_request_handler(ctx, "**.foo$", FooHandler, 0);
	mg_set_websocket_handler(ctx,
	                         "/websocket",
	                         WebSocketConnectHandler,
	                         WebSocketReadyHandler,
	                         WebsocketDataHandler,
	                         WebSocketCloseHandler,
	                         0);
	mg_set_auth_handler(ctx, "/protected", AuthHandler, 0);
	mg_stop(ctx);
	return 0;
}
