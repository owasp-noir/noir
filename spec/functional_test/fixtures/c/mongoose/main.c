// Mongoose 7.x device dashboard (shape of mongoose/tutorials/http/device-dashboard).
#include "mongoose.h"

#define API_STATS "/api/stats"

static void handle_login(struct mg_connection *c, struct mg_http_message *hm) {
  char user[64];
  struct mg_str *auth = mg_http_get_header(hm, "Authorization");
  mg_http_get_var(&hm->body, "username", user, sizeof(user));
  mg_http_reply(c, 200, "", "{}\n");
}

static void handle_settings_set(struct mg_connection *c, struct mg_str body) {
  long brightness = mg_json_get_long(body, "$.brightness", 0);
  char *name = mg_json_get_str(body, "$.device_name");
  mg_http_reply(c, 200, "", "{%ld}\n", brightness);
  free(name);
}

static void fn(struct mg_connection *c, int ev, void *ev_data) {
  if (ev == MG_EV_HTTP_MSG) {
    struct mg_http_message *hm = (struct mg_http_message *) ev_data;
    // mg_match(hm->uri, mg_str("/commented"), NULL) is not a route
    if (mg_match(hm->uri, mg_str("/api/login"), NULL) &&
        mg_match(hm->method, mg_str("POST"), NULL)) {
      handle_login(c, hm);
    } else if (mg_match(hm->uri, mg_str("/api/settings/set"), NULL)) {
      if (mg_strcmp(hm->method, mg_str("PUT")) == 0) {
        handle_settings_set(c, hm->body);
      }
    } else if (mg_match(hm->uri, mg_str(API_STATS), NULL)) {
      char page[10];
      mg_http_get_var(&hm->query, "page", page, sizeof(page));
      mg_http_reply(c, 200, "", "{}\n");
    } else if (mg_http_match_uri(hm, "/files/#")) {
      mg_http_reply(c, 200, "", "file\n");
    } else if (mg_match(hm->uri, mg_str("/websocket"), NULL)) {
      mg_ws_upgrade(c, hm, NULL);
    } else {
      struct mg_http_serve_opts opts = {.root_dir = "web_root"};
      mg_http_serve_dir(c, hm, &opts);
    }
  } else if (ev == MG_EV_MQTT_MSG) {
    struct mg_mqtt_message *mm = (struct mg_mqtt_message *) ev_data;
    if (mg_match(mm->topic, mg_str("/device/rx"), NULL)) {
      mg_mqtt_pub(c, NULL);
    }
  }
}

int main(void) {
  struct mg_mgr mgr;
  mg_mgr_init(&mgr);
  mg_http_listen(&mgr, "http://0.0.0.0:8000", fn, NULL);
  for (;;) mg_mgr_poll(&mgr, 1000);
  return 0;
}
