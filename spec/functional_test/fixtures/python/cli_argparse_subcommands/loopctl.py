import argparse

common = argparse.ArgumentParser(add_help=False)
common.add_argument("--region")

parser = argparse.ArgumentParser(prog="loopctl")
sub = parser.add_subparsers()
for name in ("run", "stop"):
    p = sub.add_parser(name, parents=[common])

if __name__ == "__main__":
    parser.parse_args()
