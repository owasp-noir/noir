// CivetWeb C++ wrapper (shape of civetweb/examples/embedded_cpp).
#include "CivetServer.h"

#define DATA_URI "/data"

class DataHandler : public CivetHandler
{
  public:
	bool
	handleGet(CivetServer *server, struct mg_connection *conn)
	{
		std::string s;
		if (CivetServer::getParam(conn, "id", s)) {
			mg_printf(conn, "%s", s.c_str());
		}
		return true;
	}
	bool
	handlePost(CivetServer *server, struct mg_connection *conn)
	{
		return true;
	}
};

class StatusHandler : public CivetHandler
{
  public:
	bool
	handleGet(CivetServer *server, struct mg_connection *conn)
	{
		return true;
	}
};

int
main(int argc, char *argv[])
{
	CivetServer server(options);
	DataHandler h_data;
	server.addHandler(DATA_URI, h_data);
	server.addHandler("/status", new StatusHandler());
	server.addWebSocketHandler("/ws", h_ws);
	return 0;
}
