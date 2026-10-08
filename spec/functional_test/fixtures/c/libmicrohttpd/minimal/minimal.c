/* A handler that serves every path (libmicrohttpd minimal_example). */
#include <microhttpd.h>

static enum MHD_Result
ahc_echo (void *cls, struct MHD_Connection *connection, const char *url,
          const char *method, const char *version, const char *upload_data,
          size_t *upload_data_size, void **req_cls)
{
  if (0 != strcmp (method, "GET"))
    return MHD_NO;
  const char *name = MHD_lookup_connection_value (connection, MHD_GET_ARGUMENT_KIND, "name");
  return MHD_YES;
}

int
main (int argc, char *const *argv)
{
  struct MHD_Daemon *d = MHD_start_daemon (MHD_USE_AUTO, 8080, NULL, NULL, &ahc_echo, NULL, MHD_OPTION_END);
  MHD_stop_daemon (d);
  return 0;
}
