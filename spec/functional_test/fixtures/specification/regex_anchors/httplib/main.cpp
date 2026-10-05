#include "httplib.h"
int main(){ httplib::Server svr; svr.Get(R"(^/httplib/(\d+)$)", [](const httplib::Request&, httplib::Response&){}); svr.listen("0.0.0.0", 8080); }
