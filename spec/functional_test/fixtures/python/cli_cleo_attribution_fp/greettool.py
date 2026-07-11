from cleo.commands.command import Command
from cleo.helpers import argument


class GreetCommand(Command):
    description = "Greets someone"

    def setup(self):
        # A local variable that textually looks like the class-level `name`
        # attribute, but lives inside a method body — must never hijack the
        # command's URL.
        name = "temp-setup-value"
        print(name)

    name = "greet"

    arguments = [
        argument("name", description="Who do you want to greet", optional=True),
    ]

    def handle(self) -> int:
        name = self.argument("name")
        print(f"Hello {name}")
        return 0


def main() -> int:
    from cleo.application import Application

    application = Application()
    application.add(GreetCommand())
    return application.run()


if __name__ == "__main__":
    main()
