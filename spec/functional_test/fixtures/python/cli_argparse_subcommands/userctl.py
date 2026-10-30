import argparse


def main():
    parser = argparse.ArgumentParser(prog="userctl")
    subparsers = parser.add_subparsers(dest="command", required=True)

    show_parser = subparsers.add_parser(
        "show", help="Show a user"
    )
    show_parser.add_argument("user_id")

    remove_parser = subparsers.add_parser(
        "remove",
        help="Remove a user",
    )
    remove_parser.add_argument("user_id")
    remove_parser.add_argument("--yes", action="store_true")

    args = parser.parse_args()
    print(args)


if __name__ == "__main__":
    main()
