require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python AWS Lambda Powertools" do
  options = create_test_options
  instance = Detector::Python::AwsLambdaPowertools.new options

  it "REST resolver import" do
    instance.detect("app.py", "from aws_lambda_powertools.event_handler import APIGatewayRestResolver").should be_true
  end

  it "Router from a submodule" do
    instance.detect("routes/todos.py", "from aws_lambda_powertools.event_handler.api_gateway import Router").should be_true
  end

  it "multi-line import of the ALB resolver" do
    instance.detect("app.py", "from aws_lambda_powertools.event_handler import (\n    ALBResolver,\n    Response,\n)").should be_true
  end

  it "utilities without the event handler" do
    instance.detect("app.py", "from aws_lambda_powertools import Logger, Tracer").should be_false
  end

  it "GraphQL resolver only" do
    instance.detect("app.py", "from aws_lambda_powertools.event_handler import AppSyncResolver").should be_false
  end

  it "GraphQL Router only" do
    instance.detect("app.py", "from aws_lambda_powertools.event_handler.appsync import Router").should be_false
  end

  it "REST Router in a parenthesised import" do
    instance.detect("app.py", "from aws_lambda_powertools.event_handler import (\n    Response,\n    Router,\n)").should be_true
  end

  it "non-python extension" do
    instance.detect("app.txt", "from aws_lambda_powertools.event_handler import APIGatewayRestResolver").should be_false
  end
end
