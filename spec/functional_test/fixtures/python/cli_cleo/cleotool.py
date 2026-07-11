import os

from cleo.application import Application
from cleo.commands.command import Command
from cleo.helpers import argument, option


class GreetCommand(Command):
    name = "greet"
    description = "Greets someone"

    arguments = [
        argument("name", description="Who do you want to greet", optional=True),
    ]
    options = [
        option("yell", "y", description="Shout the greeting", flag=True),
    ]

    def handle(self) -> int:
        name = self.argument("name")
        if self.option("yell"):
            name = name.upper()
        token = os.getenv("CLEO_TOKEN")
        self.line(f"Hello {name} ({token})")
        return 0


def main() -> int:
    application = Application()
    application.add(GreetCommand())
    return application.run()


if __name__ == "__main__":
    main()
