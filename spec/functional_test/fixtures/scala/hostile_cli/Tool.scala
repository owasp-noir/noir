package com.example.cli

import org.rogach.scallop._

class Conf(args: Seq[String]) extends ScallopConf(args) {
  // Comments with fake flags:
  // val fakeFlag = opt[String]("fake-flag")
  /*
  val blockFlag = opt[String]("block-flag")
  */
  val doc = """
    val docFlag = opt[String]("doc-flag")
  """

  val serve = new Subcommand("serve") {
    val braceStr = "curly { inside string"
    val port = opt[Int]("port")
    val host = opt[String]("host")
  }
  addSubcommand(serve)

  val rootOpt = opt[String]("root-flag")
  verify()
}
