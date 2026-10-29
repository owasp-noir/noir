require "../../spec_helper"
require "../../../src/utils/jackson_naming"

describe Noir::JacksonNaming do
  it "normalises strategy class names and property values" do
    Noir::JacksonNaming.strategy("PropertyNamingStrategies.SnakeCaseStrategy").should eq("snakecase")
    Noir::JacksonNaming.strategy("SNAKE_CASE").should eq("snakecase")
    Noir::JacksonNaming.strategy("com.fasterxml.jackson.databind.PropertyNamingStrategies$KebabCaseStrategy").should eq("kebabcase")
    Noir::JacksonNaming.strategy("MyCustomStrategy").should be_nil
  end

  it "reads @JsonNaming in Java and Kotlin spelling" do
    Noir::JacksonNaming.annotation_strategy("@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)").should eq("snakecase")
    Noir::JacksonNaming.annotation_strategy("@JsonNaming(PropertyNamingStrategies.UpperCamelCaseStrategy::class)").should eq("uppercamelcase")
  end

  it "translates like Jackson" do
    Noir::JacksonNaming.translate("userId", "snakecase").should eq("user_id")
    Noir::JacksonNaming.translate("userURL", "snakecase").should eq("user_url")
    Noir::JacksonNaming.translate("userId", "uppersnakecase").should eq("USER_ID")
    Noir::JacksonNaming.translate("userId", "kebabcase").should eq("user-id")
    Noir::JacksonNaming.translate("userId", "lowerdotcase").should eq("user.id")
    Noir::JacksonNaming.translate("userId", "lowercase").should eq("userid")
    Noir::JacksonNaming.translate("userId", "uppercamelcase").should eq("UserId")
    Noir::JacksonNaming.translate("userId", "lowercamelcase").should eq("userId")
  end
end
