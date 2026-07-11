import org.rogach.scallop._

class Conf(arguments: Seq[String]) extends ScallopConf(arguments) {
  val verbose = opt[Boolean]("verbose")

  val serve = new Subcommand("serve") {
    val port = opt[Int]("port")
    val file = trailArg[String]()
  }
  addSubcommand(serve)
  verify()
}

object Tool {
  def main(args: Array[String]): Unit = {
    val conf = new Conf(args)
    val token = sys.env("API_TOKEN")
    println(token)
  }
}
