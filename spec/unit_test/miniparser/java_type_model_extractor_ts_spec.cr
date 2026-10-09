require "../../spec_helper"
require "../../../src/miniparsers/java_type_model_extractor_ts"

describe Noir::TreeSitterJavaTypeModel do
  it "reads annotations, supertypes and methods" do
    source = <<-JAVA
      @Route(value = "x", layout = MainLayout.class) @RolesAllowed({"A", "B"})
      public class View extends Base<Long> implements HasUrlParameter<String> {
        @RestResource(exported = false)
        public static void run(@Param("q") String query, Map<K, V> map) {}
      }
      interface Repo extends CrudRepository<Person, Long> {}
      JAVA

    types = Noir::TreeSitterJavaTypeModel.extract(source)
    types.map(&.name).should eq ["View", "Repo"]

    view = types[0]
    view.kind.should eq "class"
    view.modifiers.should eq ["public"]
    view.annotation("Route").not_nil!.string.should eq "x"
    view.annotation("Route").not_nil!.string("layout").should eq "MainLayout"
    view.annotation("RolesAllowed").not_nil!.strings.should eq ["A", "B"]
    view.supertypes.should eq ["Base<Long>", "HasUrlParameter<String>"]

    method = view.methods[0]
    method.name.should eq "run"
    method.modifiers.should eq ["public", "static"]
    method.annotations[0].string("exported").should eq "false"
    method.params.map(&.name).should eq ["query", "map"]
    method.params[0].annotations[0].string.should eq "q"

    types[1].kind.should eq "interface"
    types[1].supertypes.should eq ["CrudRepository<Person, Long>"]
  end

  it "splits top-level type arguments" do
    Noir::TreeSitterJavaTypeModel.type_arguments("Repo<Person, Map<K, V>>").should eq ["Person", "Map<K, V>"]
    Noir::TreeSitterJavaTypeModel.type_arguments("Repo").should be_empty
    Noir::TreeSitterJavaTypeModel.simple_type_name("java.util.List<Foo>").should eq "List"
  end
end
