import org.apache.commons.cli.*

Options options = new Options()
options.addOption(Option.builder("f").longOpt("file").hasArg().desc("input file").build())
options.addOption(Option.builder().longOpt("verbose").desc("verbose output").build()); options.addOption(Option.builder("q").longOpt("quiet").desc("quiet mode").build())

CommandLine cmd = new DefaultParser().parse(options, args)
def token = System.getenv('CLI_TOKEN')
println token
