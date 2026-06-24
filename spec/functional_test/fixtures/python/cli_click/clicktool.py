import click


@click.group()
@click.option("--config", envvar="APP_CONFIG")
def cli(config):
    pass


@cli.command()
@click.option("--port", "-p", default=8080)
@click.argument("name")
def serve(port, name):
    pass


if __name__ == "__main__":
    cli()
