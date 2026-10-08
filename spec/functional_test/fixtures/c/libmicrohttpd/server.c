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
  if ((0 == strcmp (url, LOGIN_URL)) &&
      (0 == strcmp (method, MHD_HTTP_METHOD_POST)))
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
  /* Not a URL comparison: a header value check. */
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
