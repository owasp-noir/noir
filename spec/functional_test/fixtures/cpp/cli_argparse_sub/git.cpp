#include <argparse/argparse.hpp>

// Declare-then-register style: the subcommand parser is declared and wired
// up via add_subparser *before* the root option/parse_args lines appear, to
// prove attribution doesn't depend on source order.
int main(int argc, char** argv) {
  argparse::ArgumentParser program("git");
  argparse::ArgumentParser commit_cmd("commit");
  commit_cmd.add_argument("-m", "--message");
  program.add_subparser(commit_cmd);

  program.add_argument("--verbose");
  program.parse_args(argc, argv);
  return 0;
}
