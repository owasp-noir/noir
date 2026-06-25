import scopt.OParser

object Tool {
  case class Config(port: Int = 0, file: String = "")
  val builder = OParser.builder[Config]
  val parser = {
    import builder._
    OParser.sequence(
      opt[Int]('p', "port").action((x, c) => c.copy(port = x)),
      cmd("serve").children(
        arg[String]("<file>").action((x, c) => c.copy(file = x))
      )
    )
  }
  def main(args: Array[String]): Unit = {
    val token = sys.env("API_TOKEN")
    println(token)
  }
}
