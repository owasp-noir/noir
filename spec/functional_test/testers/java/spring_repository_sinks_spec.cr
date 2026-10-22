require "../../func_spec.cr"

# A repository call is a `sql` sink by the receiver's declared type, not
# its name: `this.owners.save` on `private final OwnerRepository owners;`
# (spring-petclinic carried no sql sink on any handler).
describe "--ai-context sql sinks on Spring Data repositories", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reads the receiver's declared type, and only its data-access methods" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/java/spring_repository_sinks/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    sql = app.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep.ai_context.try(&.sinks.select(&.kind.==("sql")).map(&.name)) || [] of String}
    end

    sql["POST /owners/new"].should eq(["this.owners.save"])
    # `@ModelAttribute findOwner` looks the owner up only under {ownerId}.
    sql["GET /owners/{ownerId}"].should eq(["this.owners.findById"])
    sql["GET /owners/new"].should be_empty
    app.endpoints.find! { |ep| ep.url == "/owners/new" && ep.method == "GET" }.callees.should be_empty
    # Through the same-class helper `findPage`.
    sql["GET /owners"].should eq(["owners.findByLastNameStartingWith"])
    # `PetStore extends JpaRepository`; `petTypes` is a `@Query` method.
    sql["GET /pets"].should eq(["pets.findAll"])
    sql["GET /pets/types"].should eq(["pets.petTypes"])
    # A service's `save` and a client's `findById` are not repository calls,
    # nor is `getClass` on a repository.
    sql["POST /notify"].should be_empty
    sql["GET /owners/kind"].should be_empty
  end
end
