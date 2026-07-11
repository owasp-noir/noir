import com.twitter.app.App

object Tool extends App {
  val retries = flag[Int]("retries", 3, "number of retries")
  val verbose = flag[Boolean]("verbose", false, "enable verbose output")

  def main(): Unit = {
    val token = sys.env("API_TOKEN")
    println(token)
  }
}
