import argparse


def main():
    parser = argparse.ArgumentParser(prog="selfparentctl", add_help=False)
    parser.add_argument("--config")
    sub = parser.add_subparsers()
    run = sub.add_parser("run", parents=[parser], add_help=False)
    run.add_argument("job")
    parser.parse_args()


if __name__ == "__main__":
    main()
