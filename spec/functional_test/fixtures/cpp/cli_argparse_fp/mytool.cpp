#include <argparse/argparse.hpp>

// Unrelated helper that builds its own local ArgumentParser, declared above
// main. Its options must never leak into the real root's endpoint, and it
// must never be mistaken for the root itself just because it comes first
// in the file.
argparse::ArgumentParser make_common_parser() {
  argparse::ArgumentParser common("common");
  common.add_argument("--log-level");
  return common;
}

int main(int argc, char** argv) {
  argparse::ArgumentParser program("mytool");
  program.add_argument("-v", "--verbose");
  program.add_argument("--config");
  program.parse_args(argc, argv);
  return 0;
}
