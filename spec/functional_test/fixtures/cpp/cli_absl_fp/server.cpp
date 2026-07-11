#include "absl/flags/flag.h"
#include "absl/flags/parse.h"
#include <map>
#include <string>

// Space before the paren (valid C++, some macro-invocation style guides use
// it) must still be detected and extracted.
ABSL_FLAG (int32_t, port, 8080, "port to listen on");

// A template type with a top-level comma must not truncate/misparse the
// name field.
ABSL_FLAG(std::map<std::string, int>, weights, {}, "weights map");

int main(int argc, char** argv) {
  absl::ParseCommandLine(argc, argv);
  return 0;
}
