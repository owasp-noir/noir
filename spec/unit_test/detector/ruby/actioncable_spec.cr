require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby Action Cable" do
  options = create_test_options
  instance = Detector::Ruby::ActionCable.new options

  it "detects an ApplicationCable::Channel subclass" do
    channel = <<-RB
      class ChatChannel < ApplicationCable::Channel
        def speak(data)
        end
      end
      RB
    instance.detect("app/channels/chat_channel.rb", channel).should be_true
  end

  it "detects the ActionCable.server mount in routes" do
    routes = <<-RB
      Rails.application.routes.draw do
        mount ActionCable.server => "/cable"
      end
      RB
    instance.detect("config/routes.rb", routes).should be_true
  end

  it "detects the ApplicationCable::Connection base" do
    conn = <<-RB
      module ApplicationCable
        class Connection < ActionCable::Connection::Base
        end
      end
      RB
    instance.detect("app/channels/application_cable/connection.rb", conn).should be_true
  end

  it "ignores a plain controller" do
    instance.detect("app/controllers/foo_controller.rb", "class FooController < ApplicationController\nend").should be_false
  end
end
