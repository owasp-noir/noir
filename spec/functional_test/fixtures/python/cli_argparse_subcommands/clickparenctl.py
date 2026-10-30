import click


@click.group()
def cli():
    pass


@cli.command()
@click.option("--port", help="port (default 8080")
def serve(port):
    pass


@cli.command()
@click.option("--force")
def stop(force):
    pass


if __name__ == "__main__":
    cli()
