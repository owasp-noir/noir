import picocli.CommandLine
import picocli.CommandLine.Command
import picocli.CommandLine.Option
import picocli.CommandLine.Parameters
import java.util.concurrent.Callable
import kotlin.system.exitProcess

@Command(name = "tool", mixinStandardHelpOptions = true, subcommands = [Serve::class])
class Tool : Callable<Int> {
    @Option(names = ["-v", "--verbose"], description = ["enable verbose logging"])
    var verbose: Boolean = false

    @Option(names = ["--config"], description = ["config path"])
    var config: String? = null

    override fun call(): Int {
        val token = System.getenv("API_TOKEN")
        return 0
    }
}

@Command(name = "serve")
class Serve : Callable<Int> {
    @Option(names = ["-p", "--port"], description = ["port to listen on"])
    var port: Int = 8080

    @Parameters(index = "0", description = ["config file"])
    lateinit var config: String

    override fun call(): Int {
        return 0
    }
}

fun main(args: Array<String>) {
    val exitCode = CommandLine(Tool()).execute(*args)
    exitProcess(exitCode)
}
