#include <httplib.h>

// Mock server a unit test starts on localhost; the app never serves it.
void start_fake_server() {
    httplib::Server svr;

    svr.Get("/fake/httplib", [](const httplib::Request& req, httplib::Response& res) {
        res.set_content("fake", "text/plain");
    });
}
