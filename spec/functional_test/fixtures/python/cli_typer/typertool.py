import os

import typer

app = typer.Typer()


@app.command()
def serve(
    port: int = typer.Option(8080, envvar="TYPER_PORT"),
    name: str = typer.Argument(...),
):
    token = os.getenv("TYPER_TOKEN")
    print(port, name, token)


if __name__ == "__main__":
    app()
