import argparse


def main():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--region")

    parser = argparse.ArgumentParser(prog="jobctl")
    sub = parser.add_subparsers(dest="command", required=True)

    run_parser = sub.add_parser("run", parents=[common])
    run_parser.add_argument("job_id")

    stop_parser = sub.add_parser("stop", parents=[common])
    stop_parser.add_argument("job_id")

    args = parser.parse_args()
    print(args)


if __name__ == "__main__":
    main()
