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
    # Kebab / lower-dot split an acronym before its last capital; snake does not.
    Noir::JacksonNaming.translate("userURLValue", "kebabcase").should eq("user-url-value")
    Noir::JacksonNaming.translate("userURLValue", "lowerdotcase").should eq("user.url.value")
    Noir::JacksonNaming.translate("userURLValue", "snakecase").should eq("user_urlvalue")
    Noir::JacksonNaming.translate("userId", "lowerdotcase").should eq("user.id")
    Noir::JacksonNaming.translate("userId", "lowercase").should eq("userid")
    Noir::JacksonNaming.translate("userId", "uppercamelcase").should eq("UserId")
    Noir::JacksonNaming.translate("userId", "lowercamelcase").should eq("userId")
  end

  it "reads @JsonRootName and UNWRAP_ROOT_VALUE (#3271)" do
    Noir::JacksonNaming.annotation_root_name(%(@JsonRootName("user"))).should eq("user")
    Noir::JacksonNaming.annotation_root_name(%(@com.fasterxml.jackson.annotation.JsonRootName(value = "user"))).should eq("user")
    Noir::JacksonNaming.annotation_root_name(%(@JsonRootName(""))).should be_nil
    Noir::JacksonNaming.unwrap_root_value?({"spring.jackson.deserialization.UNWRAP_ROOT_VALUE" => "true"}).should be_true
    Noir::JacksonNaming.unwrap_root_value?({"spring.jackson.deserialization.unwrap-root-value" => " TRUE "}).should be_true
    Noir::JacksonNaming.unwrap_root_value?({"spring.jackson.deserialization.UNWRAP_ROOT_VALUE" => "false"}).should be_false
    Noir::JacksonNaming.unwrap_root_value?({"spring.jackson.serialization.WRAP_ROOT_VALUE" => "true"}).should be_false
  end
end
