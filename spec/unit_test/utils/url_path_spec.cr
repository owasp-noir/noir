require "../../spec_helper"
require "../../../src/utils/url_path"

describe "Noir::URLPath.join" do
  it "joins parent and child without slashes" do
    Noir::URLPath.join("/api", "users").should eq("/api/users")
  end

  it "joins parent with trailing slash and child without leading slash" do
    Noir::URLPath.join("/api/", "users").should eq("/api/users")
  end

  it "joins parent without trailing slash and child with leading slash" do
    Noir::URLPath.join("/api", "/users").should eq("/api/users")
  end

  it "joins parent with trailing slash and child with leading slash" do
    Noir::URLPath.join("/api/", "/users").should eq("/api/users")
  end

  it "returns child if parent is empty" do
    Noir::URLPath.join("", "/users").should eq("/users")
  end

  it "returns parent if child is empty" do
    Noir::URLPath.join("/api", "").should eq("/api")
  end

  it "handles empty strings for both" do
    Noir::URLPath.join("", "").should eq("")
  end

  it "preserves double slashes inside paths" do
    Noir::URLPath.join("/api//v1", "users").should eq("/api//v1/users")
  end
end

# `join_trimmed` replaced seven byte-identical `join_paths` copies (http4k,
# JAX-RS, Micronaut, the shared JVM lambda-DSL extractor, AdonisJS, Elysia,
# and the Scala Play analyzer). It sits next to `join` and is easy to reach
# for by mistake, so these pin the cases where the two disagree.
describe "Noir::URLPath.join_trimmed" do
  it "collapses every slash at the seam, not just one" do
    Noir::URLPath.join_trimmed("/api//", "/users").should eq "/api/users"
    Noir::URLPath.join_trimmed("/api", "//users").should eq "/api/users"
    Noir::URLPath.join_trimmed("/api///", "///users").should eq "/api/users"
  end

  it "drops a trailing slash when the suffix is empty" do
    Noir::URLPath.join_trimmed("/api/", "").should eq "/api"
    Noir::URLPath.join_trimmed("/api", "").should eq "/api"
  end

  # The regression this file exists to pin: trimming a root-mounted prefix
  # emptied it, and an endpoint with an empty URL is dropped wholesale by
  # `EndpointOptimizer#optimize_endpoints`. A JAX-RS `@Path("/")` class with
  # a bare `@GET` method resolves through exactly this pair.
  it "keeps the root when trimming would empty a non-empty prefix" do
    Noir::URLPath.join_trimmed("/", "").should eq "/"
    Noir::URLPath.join_trimmed("//", "").should eq "/"
    Noir::URLPath.join_trimmed("///", "").should eq "/"
  end

  it "still returns the empty string only when both sides are empty" do
    Noir::URLPath.join_trimmed("", "").should eq ""
  end

  it "returns the suffix untouched when the prefix is empty" do
    Noir::URLPath.join_trimmed("", "/users").should eq "/users"
    Noir::URLPath.join_trimmed("", "users").should eq "users"
  end

  it "agrees with join on already-normalised segments" do
    [{"/api", "users"}, {"/api/", "/users"}, {"/api", "/users"}].each do |prefix, suffix|
      Noir::URLPath.join_trimmed(prefix, suffix).should eq Noir::URLPath.join(prefix, suffix)
    end
  end

  # The reason it is a separate method rather than a call to `join`.
  it "differs from join where the seam has repeated or trailing slashes" do
    Noir::URLPath.join("/api//", "/users").should eq "/api//users"
    Noir::URLPath.join_trimmed("/api//", "/users").should eq "/api/users"

    Noir::URLPath.join("/api/", "").should eq "/api/"
    Noir::URLPath.join_trimmed("/api/", "").should eq "/api"
  end
end

# The Spring mapping-composition rule, shared by the Java and Kotlin
# tree-sitter route extractors.
describe "Noir::URLPath.join_absorbing" do
  it "absorbs a bare method mapping onto the class prefix" do
    Noir::URLPath.join_absorbing("/api/article", "").should eq "/api/article"
    Noir::URLPath.join_absorbing("/api/article/", "").should eq "/api/article"
  end

  it "keeps the root when an all-slash prefix has no path" do
    Noir::URLPath.join_absorbing("/", "").should eq "/"
    Noir::URLPath.join_absorbing("///", "").should eq "/"
  end

  it "carries an explicit @GetMapping(\"/\") through the seam" do
    Noir::URLPath.join_absorbing("/api", "/").should eq "/api/"
  end

  # Deliberate: an unmapped class with a bare mapping resolves to `""`, and
  # the extractors rely on that staying empty so the analyzer above them can
  # apply the context path. Adding a root guard here would silently move
  # every JVM route — `join_rooted` exists for callers that need one.
  it "returns the path untouched when the prefix is empty" do
    Noir::URLPath.join_absorbing("", "/users").should eq "/users"
    Noir::URLPath.join_absorbing("", "").should eq ""
  end

  # They used to disagree here — `join_trimmed("/", "")` was `""` — and that
  # disagreement was the bug, not a design difference. The two rules coincide
  # on every input now, and `join_trimmed` delegates; this sweeps the empty /
  # `"/"` / `"//"` / trailing-slash matrix so a future edit to either cannot
  # reintroduce a divergence unnoticed.
  it "agrees with join_trimmed on the whole empty/slash matrix" do
    sides = ["", "/", "//", "///", "/api", "/api/", "/api//", "users", "/users", "//users", "users/"]
    sides.each do |prefix|
      sides.each do |suffix|
        Noir::URLPath.join_trimmed(prefix, suffix).should eq Noir::URLPath.join_absorbing(prefix, suffix)
      end
    end
  end

  # Neither helper roots a bare suffix — that is `join_rooted`'s job, and the
  # JVM extractors depend on an unmapped class staying unrooted so the
  # analyzer above them can apply the context path.
  it "never emits an empty result unless both sides are empty" do
    ["/", "//", "/api", "/api/"].each do |prefix|
      Noir::URLPath.join_absorbing(prefix, "").should_not be_empty
    end
    Noir::URLPath.join_absorbing("", "").should eq ""
  end
end

# `join_rooted` replaced a top-level `def join_paths(*paths) = File.join(paths)`
# that unqualified calls in `java/spring.cr` and `kotlin/spring.cr` fell
# through to. These pin the three inputs where `File.join` was wrong and the
# two where the other `URLPath` joins would regress.
describe "Noir::URLPath.join_rooted" do
  it "absorbs an empty path instead of leaving a trailing slash" do
    Noir::URLPath.join_rooted("/portal", "").should eq "/portal"
    Noir::URLPath.join_rooted("/portal/", "").should eq "/portal"
  end

  it "roots a path that carries no leading slash" do
    Noir::URLPath.join_rooted("", "users").should eq "/users"
    Noir::URLPath.join_rooted("", "/users").should eq "/users"
  end

  it "returns the root when both sides are empty" do
    Noir::URLPath.join_rooted("", "").should eq "/"
    Noir::URLPath.join_rooted("/", "").should eq "/"
  end

  it "collapses repeated slashes at the seam" do
    Noir::URLPath.join_rooted("/api//", "/users").should eq "/api/users"
    Noir::URLPath.join_rooted("/api", "//users").should eq "/api/users"
  end

  # What the File.join-based composition used to produce. Each of these is a
  # URL Spring's servlet container would not serve at that address.
  it "differs from File.join where File.join was wrong" do
    File.join("/portal", "").should eq "/portal/"
    Noir::URLPath.join_rooted("/portal", "").should eq "/portal"

    File.join("", "users").should eq "users"
    Noir::URLPath.join_rooted("", "users").should eq "/users"

    File.join("/api//", "/users").should eq "/api//users"
    Noir::URLPath.join_rooted("/api//", "/users").should eq "/api/users"
  end

  # And why neither of the existing joins could be reused: both emit an
  # empty URL for the unmapped-class-with-bare-mapping case. (Only for that
  # case now — `join_trimmed("/", "")` is `"/"`, not `""`.)
  it "differs from join_trimmed and join_absorbing on the empty pair" do
    Noir::URLPath.join_trimmed("", "").should eq ""
    Noir::URLPath.join_absorbing("", "").should eq ""
    Noir::URLPath.join_rooted("", "").should eq "/"
  end
end

# Relocated verbatim from `spec/unit_test/utils/utils_spec.cr`, where they
# covered the top-level `join_path`. Only the receiver changed — the
# assertions standing unaltered is the evidence the move preserved
# behaviour.
describe "Noir::URLPath.absolute_join" do
  it "joins two segments" do
    Noir::URLPath.absolute_join("/api", "users").should eq("/api/users")
  end

  it "collapses a double slash at the boundary" do
    Noir::URLPath.absolute_join("/api", "/users").should eq("/api/users")
  end

  it "strips trailing slashes from segments" do
    Noir::URLPath.absolute_join("api/", "/v1/").should eq("/api/v1")
  end

  it "skips empty segments" do
    Noir::URLPath.absolute_join("", "users").should eq("/users")
  end

  it "joins three segments (variadic)" do
    Noir::URLPath.absolute_join("a", "b", "c").should eq("/a/b/c")
  end

  it "always prepends a leading slash" do
    Noir::URLPath.absolute_join("noslash").should eq("/noslash")
  end

  # An all-slash segment — Compojure's `(context "/" ...)`, an all-slash
  # WebFlux prefix — is not empty on entry, so rejecting empties before
  # trimming left it in the join as an empty component.
  it "drops a segment that is empty only after trimming" do
    Noir::URLPath.absolute_join("/api", "/", "users").should eq("/api/users")
    Noir::URLPath.absolute_join("/api", "//", "users").should eq("/api/users")
    Noir::URLPath.absolute_join("/", "users").should eq("/users")
    Noir::URLPath.absolute_join("/api", "/").should eq("/api")
  end

  it "never emits a double slash from any all-slash segment" do
    ["/", "//", "///"].each do |slashes|
      Noir::URLPath.absolute_join("/api", slashes, "users").should_not contain("//")
    end
  end

  it "roots an all-slash-only join" do
    Noir::URLPath.absolute_join("/").should eq("/")
    Noir::URLPath.absolute_join("", "").should eq("/")
  end
end

describe "Noir::URLPath.strip_regex_anchors" do
  it "drops boundary anchors and unescapes dots" do
    Noir::URLPath.strip_regex_anchors("^/admin/.*$").should eq("/admin/.*")
    Noir::URLPath.strip_regex_anchors("^tags/?$").should eq("tags/?")
    Noir::URLPath.strip_regex_anchors("articles/\\.json\\Z").should eq("articles/.json")
    Noir::URLPath.strip_regex_anchors("/price/$").should eq("/price/")
  end

  it "leaves a `^` or `$` that is not at the boundary" do
    Noir::URLPath.strip_regex_anchors("/keep$mid").should eq("/keep$mid")
    Noir::URLPath.strip_regex_anchors("/a/[^/]+").should eq("/a/[^/]+")
  end

  it "tells a top-level alternation from one inside a group" do
    Noir::URLPath.top_level_alternation?("(^/a$)|(^/b$)").should be_true
    Noir::URLPath.top_level_alternation?("a|b").should be_true
    Noir::URLPath.top_level_alternation?("(?:a|b)$").should be_false
    Noir::URLPath.top_level_alternation?("api/\\|x").should be_false
  end

  it "reads an anchored regex wrapped in one group without the group" do
    Noir::URLPath.strip_regex_anchors("(^/items/(.+)/files$)").should eq("/items/(.+)/files")
    Noir::URLPath.strip_regex_anchors("(^/a/\\))").should eq("/a/\\)")
    # Alternations and partial groups keep their parentheses.
    Noir::URLPath.strip_regex_anchors("(^/a$)|(^/b$)").should eq("(^/a$)|(^/b$)")
    Noir::URLPath.strip_regex_anchors("(^/a$|^/b$)").should eq("(^/a$|^/b$)")
    Noir::URLPath.strip_regex_anchors("(^/a)/b$").should eq("(^/a)/b")
  end
end

private alias RouteSyntax = Noir::URLPath

describe "adapter route spellings" do
  # A whole-segment dedup key is too restrictive for these adapters. Exercise
  # matches with neighboring literals, malformed syntax and digit-leading names.
  {
    {RouteSyntax::COLON_WORD, ":9/:a-b", %w[9 a]},
    {RouteSyntax::COLON_IDENT, ":9/pre:id.json", %w[id]},
    {RouteSyntax::COLON_ASCII, ":9/pre:id-x", %w[id]},
    {RouteSyntax::COLON_SEGMENT_ASCII, ":a/pre:b/:c.json", %w[a c]},
    {RouteSyntax::SEGMENT_COLON_IDENT, ":a/text\n:b/:c.json", %w[a c]},
    {RouteSyntax::COLON_OR_STAR, "x:a/*b/*9", %w[a b]},
    {RouteSyntax::COLON_OR_STAR_ASCII, "x:a/*b/#c", %w[a b]},
    {RouteSyntax::COLON_STAR_HASH, ":a/*b/#c/#1", %w[a b c]},
    {RouteSyntax::COLON_OR_STAR_HYPHEN, ":a-b/*c-d", %w[a-b c-d]},
    {RouteSyntax::COLON_DOTTED, ":a.b-c/:9", %w[a.b-c]},
    {RouteSyntax::BRACE_DOTTED, "{a.b-c}/{9}", %w[a.b-c]},
    {RouteSyntax::BRACE_WORD, "{9}/{id?}/{id}", %w[9 id]},
    {RouteSyntax::BRACE_IDENT, "{_ok}/{9}/{a-b}", %w[_ok]},
    {RouteSyntax::BRACE_ASCII, "{a}_{b}/{2}", %w[a b]},
    {RouteSyntax::BRACE_CATCH_ALL, "{*1}/{**id}/{id}", %w[1 id]},
    {RouteSyntax::BRACE_REST_WORD, "{***9}/{id}", %w[9 id]},
    {RouteSyntax::BRACE_REST_IDENT, "{***a}/{9}", %w[a]},
    {RouteSyntax::SLASH_SPLAT_IDENT, "*a/*b/*9", %w[b]},
    {RouteSyntax::SPLAT_WORD, "*1/x*b", %w[1 b]},
    {RouteSyntax::BRACE_REST_PIPE, "{**id|.*}/{9}/{x:int}", %w[id 9]},
    {RouteSyntax::BRACE_CONVERTER, "{id:int}/{9}/{name}/{x:[0-9]+}", %w[id name]},
    {RouteSyntax::BRACE_TYPED, "{id:int}/{name}", %w[id]},
    {RouteSyntax::BRACE_CONVERTER_FIRST, "{ int:id}/{int : slug}/{x}", %w[slug x]},
    {RouteSyntax::BRACE_CONSTRAINT, "{with space:.*}/{id:[0-9]{2}}/{empty:}", ["with space"]},
    {RouteSyntax::BRACE_TYPED_ASCII, "{id:[0-9]+}/{9:x}/{empty:}", %w[id]},
    {RouteSyntax::BRACE_WITH_CONSTRAINT, "{id:[0-9]+}/{name}/{9}/{x:}", %w[id name]},
    {RouteSyntax::BRACE_FLAT_CONSTRAINT, "{id:}/{id:[0-9]{2}}/{name}", %w[id name]},
    {RouteSyntax::BRACE_OPTIONAL_CONSTRAINT, "{9?:abc}/{x?}/{y:[0-9]{2}}", %w[9 x 2]},
    {RouteSyntax::BRACE_WORD_CONSTRAINT, "{9:.*}/{x:}/{y}", %w[9 y]},
    {RouteSyntax::BRACE_TYPED_WORD, "{9:.*}/{x}/{y:}", %w[9]},
    {RouteSyntax::BRACE_OR_SPLAT, "*tail/{a:.*}/*tail/{2}", %w[tail a tail]},
    {RouteSyntax::COLON_TYPED, ":id:int/:9/:other", %w[id other]},
    {RouteSyntax::COLON_OPTIONAL, ":a?/:b/:9?", %w[a b]},
    {RouteSyntax::COLON_ANGLE_CONSTRAINT, ":9<>/:a<.*>", %w[9 a]},
    {RouteSyntax::ANGLE_PIPE, "<id|[0-9]*>/<x>/<9>", %w[id x]},
    {RouteSyntax::ANGLE_WORD, "<9>/<name:int>", %w[9]},
    {RouteSyntax::ANGLE_WORD_TYPED, "<9:uint>/<id:x>/<bad:>", %w[9 id]},
    {RouteSyntax::ANGLE_NAME_TYPED, "<9:uint>/<id:x>/<x>", %w[id x]},
    {RouteSyntax::ANGLE_CONVERTER_FIRST, "<int:id>/<x>/<id:9>", %w[id x]},
    {RouteSyntax::ANGLE_BODY, "<x:int>/< id >/<:>", ["x:int", " id ", ":"]},
    {RouteSyntax::DOLLAR_OPTIONAL_BRACES, "${foo/$bar}/$9", %w[foo bar]},
    {RouteSyntax::DOLLAR_BRACED_IDENT, "${a}/$b", %w[a]},
    {RouteSyntax::DOLLAR_IDENT, "${a}/$b", %w[b]},
    {RouteSyntax::DOLLAR_REGEX, "$id<[0-9]+>/$b/$2<.>", %w[id 2]},
    {RouteSyntax::NAMED_CAPTURE, "(?<x>.+)/(?P<y>.)", %w[x]},
  }.each do |pattern, path, expected|
    it "reads #{path.inspect} with #{pattern.inspect}" do
      RouteSyntax.names(path, pattern).should eq(expected)
    end
  end

  it "applies each adapter's replacement and slash choices independently" do
    RouteSyntax.normalize("a//:id(\\d+)/", RouteSyntax::COLON_IDENT).should eq("/a//{id}(\\d+)/")
    RouteSyntax.normalize("a//:id:int/", RouteSyntax::COLON_TYPED, collapse: true, trim: true).should eq("/a/{id}")
    RouteSyntax.normalize(":id?", RouteSyntax::COLON_OPTIONAL, rooted: false).should eq("{id}")
    RouteSyntax.normalize("<a|.*>/", RouteSyntax::ANGLE_PIPE, rooted: false).should eq("{a}/")
    RouteSyntax.normalize("/x/{a.b}", RouteSyntax::BRACE_DOTTED, replacement: ":\\1").should eq("/x/:a.b")
    RouteSyntax.normalize("{n:[0-9]{2}}", RouteSyntax::BRACE_CONSTRAINT).should eq("/{n:[0-9]{2}}")
    RouteSyntax.normalize(":${id}/$slug", *RouteSyntax::DOLLAR_SLOTS).should eq("/:{id}/{slug}")
    RouteSyntax.normalize("a///", trim: true).should eq("/a//")
    RouteSyntax.normalize("", empty: "").should eq("")
    RouteSyntax.normalize("").should eq("/")
    RouteSyntax.request_path("a//x/#frag?query").should eq("/a/x")
    RouteSyntax.request_path("?x").should eq("/")
    RouteSyntax.normalize_prefixed_template(" //a///b/ ").should eq("//a/b/")
    RouteSyntax.normalize_prefixed_template("///").should eq("/")
    RouteSyntax.trimmed_segments(" a / // b ").should eq(%w[a b])
    RouteSyntax.brace_interpolation(%q(#{ var }/x)).should eq("{var}/x")
  end

  it "keeps pass order and duplicates unless its caller requests deduplication" do
    path = "/{a}/:z/{z}/:z"
    RouteSyntax.params(path, *RouteSyntax::COLON_THEN_BRACE).map(&.name).should eq(%w[z z a z])
    RouteSyntax.params(path, *RouteSyntax::COLON_THEN_BRACE, unique: true).map(&.name).should eq(%w[z a])
    endpoint = Endpoint.new(path, "GET", [Param.new("z", "", "query"), Param.new("a", "int", "path")])
    RouteSyntax.add_params(endpoint, path, *RouteSyntax::COLON_THEN_BRACE)
    endpoint.params.map { |p| {p.name, p.param_type, p.value} }.should eq([{"z", "query", ""}, {"a", "path", "int"}, {"z", "path", ""}])
    RouteSyntax.params("{{id:int}}", RouteSyntax::BRACE_CONVERTER, doubled_braces: true).map(&.name).should eq(["id"])
    RouteSyntax.strip_type_converters("/{{id:int}}/{rest:path}/{name:.*}").should eq("/{{id}}/{rest:path}/{name:.*}")
  end

  it "preserves optional brackets, empty sigil names and rooted prefix seams" do
    RouteSyntax.normalize("[:a]/[:b/:c]", *RouteSyntax::OPTIONAL_THEN_COLON).should eq("/{a}/[{b}/{c}]")
    RouteSyntax.normalize("[:id]suffix", *RouteSyntax::OPTIONAL_THEN_COLON).should eq("/{idsuffix}")
    route = "/@id:int/?slug/x@keep/@:empty"
    RouteSyntax.names(route, RouteSyntax::SIGIL_SEGMENT).should eq(["id", "slug", ""])
    RouteSyntax.normalize(route, RouteSyntax::SIGIL_SEGMENT).should eq("/{id}/{slug}/x@keep/{}")
    RouteSyntax.join("/", "/x", :preserve_root_prefix).should eq("//x")
    RouteSyntax.join("a//", "", :preserve_root_prefix).should eq("a//")
  end

  it "uses the same matches for replacements and parameters" do
    path, params = RouteSyntax.rewrite_params("<int:id>_<id>", RouteSyntax::ANGLE_CONVERTER_FIRST, unique: true)
    path.should eq("{id}_{id}")
    params.map(&.name).should eq(["id"])
    RouteSyntax.rewrite_names("< id :int>/<:>", RouteSyntax::ANGLE_BODY, colon: true) { |m| m[1].split(':').first.strip }.should eq({":id/:", ["id", ""]})
  end

  it "retains optional, default and catch-all name conventions" do
    route = "/{**tail}/{id:int=4}/{odd*}/{a/b}/{?}"
    RouteSyntax.template_names(route).should eq(["tail", "id", "odd*", "a/b", ""])
    RouteSyntax.template_names(route, RouteSyntax::BRACE_SEGMENT_BODY, trailing_star: true).should eq(["tail", "id", "odd", ""])
    RouteSyntax.bind_optional_slots("/{missing?}/items/{id:int?}/{page=1}", ["id"]).should eq("/items/{id:int}/{page}")
  end

  it "uses the file router's catch-all spelling and first matched segment" do
    RouteSyntax.bracket_segment("[id]").should eq("{id}")
    RouteSyntax.bracket_segment("[...id]").should eq("{id}")
    RouteSyntax.bracket_segment("[[...id]]").should eq("[[...id]]")
    RouteSyntax.bracket_segment("[[...id]]", catch_all: true).should eq("{*id}")
    RouteSyntax.bracket_segment("[...id]]", catch_all: true).should eq("{*id}")
    RouteSyntax.bracket_segment("x[id]").should eq("x[id]")
  end

  it "handles empty operands, the seam and interior slashes separately" do
    RouteSyntax.join("", "", :collapsed).should eq("/")
    RouteSyntax.join("api//v1/", "", :collapsed).should eq("/api/v1/")
    RouteSyntax.join("/a//", "///b/", :trim_seam).should eq("/a/b/")
    RouteSyntax.join("/a//", "", :trim_seam).should eq("/a//")
    RouteSyntax.join("", "users", :chomp_prefix).should eq("users")
    RouteSyntax.join("", "users", :root_child).should eq("/users")
    RouteSyntax.join("/a//", "//b", :root_child).should eq("/a///b")
    RouteSyntax.join("a/", "///", :rooted_mount).should eq("/a")
    RouteSyntax.join("/", "//x", :rooted_mount).should eq("//x")
    RouteSyntax.join("", "users", :require_seam).should eq("/users")
    RouteSyntax.join("api", "", :require_seam).should eq("api/")
    RouteSyntax.join("", "", :require_seam).should eq("/")
  end
end
