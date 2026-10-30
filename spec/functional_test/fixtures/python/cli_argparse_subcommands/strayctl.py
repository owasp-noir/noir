import argparse


def main():
    parser = argparse.ArgumentParser(prog="strayctl", description="Stray tool (beta")
    sub = parser.add_subparsers(dest="command")
    # NOTE: sub.add_parser( must be called before use
    a = sub.add_parser("alpha", help="list things :(")
    a.add_argument("--aa", help="alpha (beta")
    b = sub.add_parser("beta")
    b.add_argument("--bb")
    out = b.add_argument_group("output")
    out.add_argument("--json", action="store_true")
    mode = b.add_mutually_exclusive_group()
    mode.add_argument("--quiet", action="store_true")
    print(f"call add_argument({a!r}")
    c = sub.add_parser("gamma")
    c.add_argument("--cc")
    parser.parse_args()


if __name__ == "__main__":
    main()
