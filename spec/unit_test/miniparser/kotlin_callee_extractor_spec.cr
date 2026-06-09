require "../../spec_helper"
require "../../../src/miniparsers/kotlin_callee_extractor"

private def with_kotlin_root(source : String, &)
  Noir::TreeSitter.parse_kotlin(source) do |root|
    yield root
  end
end

# Recursive walker — Noir::TreeSitter only exposes `each_named_child`,
# so spec helpers do their own DFS over named children.
private def walk_named(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
  block.call(node)
  Noir::TreeSitter.each_named_child(node) do |child|
    walk_named(child, &block)
  end
end

describe Noir::KotlinCalleeExtractor do
  describe ".callees_in_method" do
    it "captures unqualified, qualified, this-, and static-receiver calls" do
      source = <<-KT
        package app

        class UserController {
            fun show(id: Long): String {
                val user = service.findById(id)
                this.validate(user)
                return Renderer.html(user)
            }
            fun validate(u: Any) {}
        }
        KT

      callees = nil
      with_kotlin_root(source) do |root|
        callees = Noir::KotlinCalleeExtractor.callees_in_method(
          root, source, "UserController.kt", "UserController", "show"
        )
      end
      names = callees.not_nil!.map(&.[0])

      names.should contain("service.findById")
      names.should contain("this.validate")
      names.should contain("Renderer.html")
    end

    it "returns empty when class/method cannot be found" do
      source = "class A { fun m() {} }"

      with_kotlin_root(source) do |root|
        Noir::KotlinCalleeExtractor.callees_in_method(root, source, "A.kt", "MissingClass", "m").should be_empty
        Noir::KotlinCalleeExtractor.callees_in_method(root, source, "A.kt", "A", "missingFn").should be_empty
      end
    end

    it "uses route line to disambiguate overloaded methods" do
      source = <<-KT
        package app

        class GraphqlController {
            @SchemaMapping
            fun author(article: Article): User =
                service.findArticleAuthor(article.authorId)

            @SchemaMapping
            fun author(comment: Comment): User =
                service.findCommentAuthor(comment.userId)
        }
        KT

      with_kotlin_root(source) do |root|
        default_names = Noir::KotlinCalleeExtractor.callees_in_method(
          root, source, "GraphqlController.kt", "GraphqlController", "author"
        ).map(&.[0])
        comment_names = Noir::KotlinCalleeExtractor.callees_in_method(
          root, source, "GraphqlController.kt", "GraphqlController", "author", 8
        ).map(&.[0])

        default_names.should contain("service.findArticleAuthor")
        comment_names.should contain("service.findCommentAuthor")
        comment_names.should_not contain("service.findArticleAuthor")
      end
    end

    it "captures enum entries property access without treating arbitrary fields as callees" do
      source = <<-KT
        package app

        enum class RoleType { ADMIN, USER }
        class RoleController {
            fun getTypes(): List<RoleType> {
                val types = RoleType.entries
                val id = currentUser.id
                return types
            }
        }
        KT

      with_kotlin_root(source) do |root|
        names = Noir::KotlinCalleeExtractor.callees_in_method(
          root, source, "RoleController.kt", "RoleController", "getTypes"
        ).map(&.[0])

        names.should contain("RoleType.entries")
        names.should_not contain("currentUser.id")
      end
    end

    it "guards against empty class_name or method_name" do
      source = "class A { fun m() {} }"
      with_kotlin_root(source) do |root|
        Noir::KotlinCalleeExtractor.callees_in_method(root, source, "A.kt", "", "m").should be_empty
        Noir::KotlinCalleeExtractor.callees_in_method(root, source, "A.kt", "A", "").should be_empty
      end
    end
  end

  describe ".callees_in_lambda (Ktor mode, skip_routing: true)" do
    it "treats nested verb DSL calls as route boundaries and skips their callees" do
      source = <<-KT
        package app

        fun module() {
            routing {
                get("/users") {
                    outerHelper()
                    route("/admin") {
                        adminOnly()
                    }
                }
            }
        }
        KT

      callees = nil
      with_kotlin_root(source) do |root|
        # Locate the GET handler's lambda body — `get("/users") { ... }`.
        # Walk the AST to find the call_expression for `get` and grab
        # its trailing lambda statements node.
        target_body : LibTreeSitter::TSNode? = nil
        walk_named(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          # Crude but effective: match by source substring.
          text = Noir::TreeSitter.node_text(node, source)
          next unless text.starts_with?("get(\"/users\")")
          # The handler lambda's `statements` node is the body we
          # actually want to feed into the extractor.
          walk_named(node) do |inner|
            if Noir::TreeSitter.node_type(inner) == "statements" && target_body.nil?
              target_body = inner
            end
          end
        end

        target_body.should_not be_nil
        callees = Noir::KotlinCalleeExtractor.callees_in_lambda(
          target_body.not_nil!, source, "Module.kt", skip_routing: true
        )
      end
      names = callees.not_nil!.map(&.[0])

      names.should contain("outerHelper")
      # Nested route's body is skipped entirely; its inner callees
      # must not leak into the parent route's list.
      names.should_not contain("adminOnly")
      # The `route` verb itself is part of the routing DSL — must not
      # surface as a regular callee under skip_routing.
      names.should_not contain("route")
    end
  end

  describe ".callees_in_lambda (http4k mode, skip_routing: false)" do
    it "keeps calls named like routing verbs (http4k uses `bind` not nested route blocks)" do
      source = <<-KT
        fun handler() {
            val req = get()
            val res = post("data")
            return res
        }
        KT

      callees = nil
      with_kotlin_root(source) do |root|
        target_body : LibTreeSitter::TSNode? = nil
        walk_named(root) do |node|
          if Noir::TreeSitter.node_type(node) == "function_body" && target_body.nil?
            target_body = node
          end
        end
        target_body.should_not be_nil
        callees = Noir::KotlinCalleeExtractor.callees_in_lambda(
          target_body.not_nil!, source, "Routes.kt", skip_routing: false
        )
      end
      names = callees.not_nil!.map(&.[0])

      # In http4k mode, even `get`/`post` are regular calls and must
      # surface — turning them into "routing DSL" boundaries would
      # silently drop real handler code.
      names.should contain("get")
      names.should contain("post")
    end
  end
end
