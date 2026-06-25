def cli = new CliBuilder(usage: 'tool')
cli.v(longOpt: 'verbose', 'Verbose output')
cli.p(longOpt: 'port', args: 1, 'Port number')

def options = cli.parse(args)
def token = System.getenv('API_TOKEN')
println token
