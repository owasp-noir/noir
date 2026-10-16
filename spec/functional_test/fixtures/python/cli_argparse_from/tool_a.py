from argparse import ArgumentParser
import os


def main():
    parser = ArgumentParser(prog="tool_a")
    parser.add_argument("--out-dir")
    parser.add_argument("--verbose", action="store_true")
    home = os.environ.get("HOME", "")
    args = parser.parse_args()
    print(args, home)


if __name__ == "__main__":
    main()
