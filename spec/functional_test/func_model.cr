require "../../src/models/noir.cr"

module Noir
    VERSION = "SPEC"
end

class FunctionalTester
    # expected_count's symbols are:
    # :techs
    # :endpoints
    # :params
    @expected_count : Hash(Symbol, Int32)
    @app : NoirRunner
    @path : String

    def initialize (@path, @expected_count : Hash(Symbol, Int32))
        noir_options = default_options()
        noir_options[:base] = "./spec/functional_test/#{@path}"
        noir_options[:nolog] = "yes"

        @app = NoirRunner.new noir_options
    end

    def test_detect
        @app.detect
        it "funcational test - detect => #{@path}" do
            @app.techs.size.should eq @expected_count[:techs]
        end
    end

    def test_analyze
        @app.analyze
        it "funcational test - analyze => #{@path}" do
            @app.endpoints.size.should eq @expected_count[:endpoints]
        end
    end

    def test_all
        test_detect
        test_analyze
    end
end