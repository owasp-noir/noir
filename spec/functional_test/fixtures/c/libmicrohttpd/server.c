/* libmicrohttpd access handler that routes on the URL. */
#include <string.h>
#include <microhttpd.h>

#define LOGIN_URL "/login"

static enum MHD_Result
handle_search (struct MHD_Connection *connection)
{
  const char *q = MHD_lookup_connection_value (connection, MHD_GET_ARGUMENT_KIND, "q");
  const char *lang = MHD_lookup_connection_value (connection, MHD_HEADER_KIND, "Accept-Language");
  return MHD_YES;
}

static enum MHD_Result
answer_to_connection (void *cls, struct MHD_Connection *connection,
                      const char *url, const char *method,
                      const char *version, const char *upload_data,
                      size_t *upload_data_size, void **req_cls)
{
  if ((0 == strcmp (method, MHD_HTTP_METHOD_POST)) &&
      (0 == strcmp (content_type, "application/x-www-form-urlencoded; charset=utf-8")) &&
      (0 == strcmp (url, LOGIN_URL)))
  {
    const char *user = MHD_lookup_connection_value (connection, MHD_POSTDATA_KIND, "user");
    return MHD_YES;
  }
  if (0 == strcmp (url, "/search"))
  {
    if (0 != strcmp (method, "GET"))
      return MHD_NO;
    return handle_search (connection);
  }
  if (0 == strcmp ("/session", url))
  {
    const char *sid = MHD_lookup_connection_value (connection, MHD_COOKIE_KIND, "sid");
    return MHD_YES;
  }
  if (0 == strncmp (url, "/static/", 8))
    return serve_file (connection, url + 8);
  /* Not URL comparisons: a header value check, a curl option. */
  if (0 == strcmp (curl_opt, "/tmp/curl"))
    return MHD_NO;
  if (0 == strcmp (method, "OPTIONS") || 0 == strcmp (version, "/HTTP"))
    return MHD_NO;
  return MHD_NO;
}

int
main (void)
{
  struct MHD_Daemon *daemon;
  daemon = MHD_start_daemon (MHD_USE_INTERNAL_POLLING_THREAD, 8888, NULL, NULL,
                             &answer_to_connection, NULL, MHD_OPTION_END);
  MHD_stop_daemon (daemon);
  return 0;
}
