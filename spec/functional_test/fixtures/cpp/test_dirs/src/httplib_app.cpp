#include <httplib.h>

int main() {
    httplib::Server svr;

    svr.Get("/real/httplib", [](const httplib::Request& req, httplib::Response& res) {
        res.set_content("ok", "text/plain");
    });

    svr.listen("0.0.0.0", 8080);
}
