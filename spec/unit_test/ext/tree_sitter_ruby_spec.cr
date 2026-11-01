require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

describe "Noir::TreeSitter.parse_ruby" do
  it "parses Ruby code containing idiomatic constructs without errors" do
    source = <<-'RUBY'
      class UsersController < ApplicationController
        before_action :authenticate_user!, only: [:show]

        class << self
          def config(app_name: "test")
            @app_name = app_name
          end
        end

        define_method(:foo) { }

        get '/x', to: 'a#b'

        def show
          query = <<~SQL
            SELECT * FROM users
            WHERE id = #{params[:id]}
            -- end of query
          SQL

          items = %w[alpha beta gamma]
          handler = ->(x) { x }
          val = a&.b

          [1, 2, 3].each do |num|
            puts num
          end
        end
      end
      RUBY

    types = [] of String
    has_error_node = false

    Noir::TreeSitter.parse_ruby(source) do |root|
      LibTreeSitter.ts_node_has_error(root).should be_false
      Noir::TreeSitter.node_has_error?(root).should be_false

      Noir::TreeSitter.walk(root) do |n|
        ty = Noir::TreeSitter.node_type(n)
        has_error_node = true if ty == "ERROR"
        types << ty unless ty.empty?
      end
    end

    has_error_node.should be_false
    types.should contain("call")
    types.should contain("method")
    types.should contain("heredoc_body")
    types.should contain("singleton_class")
    types.should contain("block")
    types.should contain("lambda")
    types.should contain("string_array")
  end
end
