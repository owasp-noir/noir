import picocli.CommandLine
import picocli.CommandLine.Command
import picocli.CommandLine.Option
import picocli.CommandLine.Parameters
import java.util.concurrent.Callable

@Command(name = "multitool")
class MultiTool : Callable<Int> {
    override fun call(): Int = 0
}

// Wrapped command annotation, plus annotation-and-property on the same line.
@Command(
    name = "serve",
    description = ["start the server"]
)
class Serve : Callable<Int> {
    @Option(names = ["-p", "--port"]) var port: Int = 8080
    @Parameters(index = "0") lateinit var target: String
    override fun call(): Int = 0
}

fun main(args: Array<String>) {
    CommandLine(MultiTool()).execute(*args)
}
