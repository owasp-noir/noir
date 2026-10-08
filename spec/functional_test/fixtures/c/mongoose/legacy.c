// Mongoose 6.x API: explicit endpoint registration and mg_vcmp URI checks.
#include "mongoose.h"

static void handle_sum_call(struct mg_connection *nc, int ev, void *ev_data) {
  struct http_message *hm = (struct http_message *) ev_data;
  char n1[100];
  mg_get_http_var(&hm->body, "n1", n1, sizeof(n1));
  mg_printf(nc, "HTTP/1.1 200 OK\r\n\r\n");
}

static void ev_handler(struct mg_connection *nc, int ev, void *ev_data) {
  struct http_message *hm = (struct http_message *) ev_data;
  if (ev == MG_EV_HTTP_REQUEST) {
    if (mg_vcmp(&hm->uri, "/api/v1/status") == 0) {
      char q[32];
      mg_get_http_var(&hm->query_string, "verbose", q, sizeof(q));
      mg_printf(nc, "HTTP/1.1 200 OK\r\n\r\n");
    }
  }
}

int main(void) {
  struct mg_mgr mgr;
  struct mg_connection *nc;
  mg_mgr_init(&mgr, NULL);
  nc = mg_bind(&mgr, "8000", ev_handler);
  mg_register_http_endpoint(nc, "/api/v1/sum", handle_sum_call);
  mg_set_protocol_http_websocket(nc);
  return 0;
}
