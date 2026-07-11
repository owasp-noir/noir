import os

from cleo.commands.command import Command


def make_command():
    # A Command subclass declared inside a factory function (nested/indented
    # scope). scan_cleo's extraction regex is anchored to column 0, so this
    # is never resolved into a real subcommand — cli_entrypoint? must agree
    # and not treat this file as a CLI surface on the strength of this class
    # alone.
    class DynamicCmd(Command):
        name = "dynamic"

        def handle(self):
            return 0

    return DynamicCmd


# Unrelated env read belonging to ordinary application config, not a real
# CLI entry point. Must NOT surface as a `cli://` endpoint.
api_key = os.getenv("SOME_UNRELATED_API_KEY")
