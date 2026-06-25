#include <CLI/CLI.hpp>
#include <cstdlib>
#include <string>

int main(int argc, char** argv) {
    CLI::App app{"My tool"};
    app.add_flag("-v,--verbose");

    std::string port;
    std::string config_file;

    auto* serve = app.add_subcommand("serve", "start the server");
    serve->add_option("-p,--port", port);
    serve->add_option("config", config_file);

    const char* token = std::getenv("API_TOKEN");
    CLI11_PARSE(app, argc, argv);
    return 0;
}
