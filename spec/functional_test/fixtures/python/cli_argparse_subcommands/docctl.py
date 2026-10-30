"""Doc tool.

Builds an argparse.ArgumentParser (with one subparser per command; see
main() below for the layout.
"""
import argparse


def main():
    parser = argparse.ArgumentParser(prog="docctl")
    sub = parser.add_subparsers()
    a = sub.add_parser("alpha")
    a.add_argument("--aa")
    b = sub.add_parser("beta")
    b.add_argument("--bb")
    group = b.add_argument_group("output")
    b = sub.add_parser("gamma")
    group.add_argument("--late-beta")
    b.add_argument_group("inline").add_argument("--inline")
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--region")
    run = sub.add_parser("run", parents=[common])
    run.add_argument("job")
    log.debug("not common.parse_args() here")  # nor common.parse_args()
    parser.parse_args()


if __name__ == "__main__":
    main()
