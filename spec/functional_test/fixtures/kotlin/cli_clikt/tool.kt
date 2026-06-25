import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.clikt.parameters.arguments.argument
import com.github.ajalt.clikt.parameters.options.option

class Tool : CliktCommand() {
    val verbose by option("-v", "--verbose")
    override fun run() {
        val token = System.getenv("API_TOKEN")
    }
}

class Serve : CliktCommand() {
    val port by option("-p", "--port")
    val config by argument()
    override fun run() {}
}

fun main(args: Array<String>) = Tool().subcommands(Serve()).main(args)
