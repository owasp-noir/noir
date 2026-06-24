import argparse
import os


def main():
    parser = argparse.ArgumentParser(prog="pytool")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("source")

    sub = parser.add_subparsers()
    serve = sub.add_parser("serve")
    serve.add_argument("--port", type=int, default=8080)

    args = parser.parse_args()
    token = os.environ["API_TOKEN"]
    print(args, token)


if __name__ == "__main__":
    main()
