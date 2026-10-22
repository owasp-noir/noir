import com.beust.jcommander.JCommander
import com.beust.jcommander.Parameter

class MainArgs {
    @Parameter(names = ["-f", "--file"], description = "input file")
    String file
}

class AddCommand {
    @Parameter(names = ["-m", "--message"], description = "commit message")
    String message
}

class RemoveCommand {
    @Parameter(names = ["-r", "--recursive"], description = "recursive removal")
    boolean recursive
}

def mainArgs = new MainArgs()
def addCommand = new AddCommand()

JCommander jc = JCommander.newBuilder()
    .addObject(mainArgs)
    .addCommand('add', addCommand)
    .addCommand('remove', new RemoveCommand())
    .build()

jc.parse(args)
def token = System.getenv('JC_TOKEN')
println token
