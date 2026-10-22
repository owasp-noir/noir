require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Spark" do
  options = create_test_options
  instance = Detector::Java::Spark.new options

  it "static import of spark.Spark" do
    instance.detect("App.java", "import static spark.Spark.*;").should be_true
  end
  it "import of a spark.* class" do
    instance.detect("App.java", "import spark.Request;").should be_true
  end
  it "fully qualified spark.Spark call" do
    instance.detect("App.java", "spark.Spark.get(\"/hi\", (q, r) -> \"hi\");").should be_true
  end
  it "Apache Spark SparkConf import" do
    instance.detect("Job.java", "import org.apache.spark.SparkConf;").should be_false
  end
  it "Apache Spark SparkContext import" do
    instance.detect("Job.java", "import org.apache.spark.SparkContext;").should be_false
  end
  it "Apache Spark in pom.xml" do
    instance.detect("pom.xml", "import org.apache.spark.SparkConf;").should be_false
  end
end
