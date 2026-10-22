import org.rogach.scallop._

class Conf(arguments: Seq[String]) extends ScallopConf(arguments) {
  val verbose = opt[Boolean]("verbose")

  object serve extends Subcommand("serve") {
    val port = opt[Int]()
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
