require "spec"
require "../../../src/miniparsers/java_route_extractor_ts"

# A static import seeds bare constant names ahead of the file's own fields; the
# file's own declaration must win, and the wildcard form must resolve through
# the table's per-class index (`ProjectConstants#constants_of`).
describe "Noir::TreeSitterJavaRouteExtractor static imports and own constants" do
  plain = {
    "com.example.Commons.BASE"       => "/commons",
    "com.example.Commons.ADMIN"      => "/admin",
    "com.example.Commons.Inner.DEEP" => "/deep",
    "com.example.Other.BASE"         => "/other",
    "Commons.BASE"                   => "/commons",
  }
  indexed = Noir::TreeSitterJavaRouteExtractor::ProjectConstants.new
  plain.each { |key, value| indexed[key] = value }

  extract = ->(source : String, table : Hash(String, String)) do
    constants = Hash(String, String).new
    Noir::TreeSitter.parse_java(source) do |root|
      constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source, table)
    end
    constants
  end

  {"plain Hash" => plain, "ProjectConstants" => indexed}.each do |label, table|
    describe "with a #{label} table" do
      it "lets the file's own field win over a wildcard import of the same name" do
        constants = extract.call(<<-JAVA, table)
          import static com.example.Commons.*;

          class Local {
              static final String BASE = "/local";
              static final String API = BASE + "/v1";
          }
          JAVA

        constants["BASE"].should eq("/local")
        constants["API"].should eq("/local/v1")
        constants["ADMIN"].should eq("/admin")
        constants.has_key?("DEEP").should be_false
      end

      it "lets the file's own field win over a single static import of the same name" do
        constants = extract.call(<<-JAVA, table)
          import static com.example.Commons.BASE;

          class Local {
              static final String BASE = "/local";
          }
          JAVA

        constants["BASE"].should eq("/local")
      end

      it "still resolves an imported name the file does not declare" do
        constants = extract.call(<<-JAVA, table)
          import static com.example.Commons.*;

          class Local {
              static final String API = BASE + "/v1";
          }
          JAVA

        constants["BASE"].should eq("/commons")
        constants["API"].should eq("/commons/v1")
      end

      it "binds nothing for a class the table has no constants for" do
        constants = extract.call(<<-JAVA, table)
          import static com.example.Missing.*;

          class Local {}
          JAVA

        constants.has_key?("BASE").should be_false
      end
    end
  end

  it "indexes each class's direct constants once" do
    indexed.constants_of("com.example.Commons").not_nil!.sort!.should eq([{"ADMIN", "/admin"}, {"BASE", "/commons"}])
    indexed.constants_of("com.example.Commons.Inner").should eq([{"DEEP", "/deep"}])
    indexed.constants_of("com.example.Nope").should be_nil
  end
end
