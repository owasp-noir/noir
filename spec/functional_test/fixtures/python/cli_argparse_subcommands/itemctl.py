import argparse


def main():
    parser = argparse.ArgumentParser(prog="itemctl")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("list", help="List items")
    p.add_argument("--limit", type=int)

    p = sub.add_parser("get", help="Get one item")
    p.add_argument("item_id")

    p = sub.add_parser("delete", help="Delete an item")
    p.add_argument("item_id")
    p.add_argument("--force", action="store_true")

    args = parser.parse_args()
    print(args)


if __name__ == "__main__":
    main()
