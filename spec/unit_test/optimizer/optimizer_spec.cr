require "file_utils"
require "../../spec_helper"
require "../../../src/optimizer/optimizer"
require "../../../src/models/endpoint"
require "../../../src/models/logger"

describe "EndpointOptimizer" do
  options = create_test_options
  logger = NoirLogger.new(false, false, false, false)

  describe "optimize_endpoints" do
    it "removes duplicated endpoints" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/api/users", "GET"),
        Endpoint.new("/api/users", "GET"), # duplicate
        Endpoint.new("/api/users", "POST"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result.size.should eq(2)
      result[0].method.should eq("GET")
      result[1].method.should eq("POST")
    end

    it "normalizes HTTP methods" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/test", "INVALID_METHOD"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].method.should eq("GET")
    end

    it "preserves ANY as a valid HTTP method" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/test", "ANY"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].method.should eq("ANY")
    end

    it "canonicalizes valid methods to upper case" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/test", "get"),
        Endpoint.new("/test", "Post"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result.map(&.method).should eq(["GET", "POST"])
    end

    it "deduplicates endpoints whose methods differ only in case" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/api/users", "get"),
        Endpoint.new("/api/users", "GET"), # same endpoint, different casing
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result.size.should eq(1)
      result[0].method.should eq("GET")
    end

    it "merges callees and code paths from duplicated endpoints" do
      optimizer = EndpointOptimizer.new(logger, options)
      interface_endpoint = Endpoint.new(
        "/api/users", "GET", Details.new(PathInfo.new("UserApi.kt", 10))
      )
      implementation_endpoint = Endpoint.new(
        "/api/users", "GET", Details.new(PathInfo.new("UserController.kt", 20))
      )
      implementation_endpoint.push_callee(Callee.new("service.list", path: "UserController.kt", line: 21))

      result = optimizer.optimize_endpoints([interface_endpoint, implementation_endpoint])

      result.size.should eq(1)
      result[0].callees.map(&.name).should eq(["service.list"])
      result[0].details.code_paths.map(&.path).should eq(["UserApi.kt", "UserController.kt"])
    end

    it "keeps identical endpoints from separate build modules distinct" do
      optimizer = EndpointOptimizer.new(logger, options)
      temp_dir = File.join(Dir.tempdir, "noir-optimizer-modules-#{Process.pid}-#{Time.utc.to_unix_ms}")
      module_a = File.join(temp_dir, "data-r2dbc")
      module_b = File.join(temp_dir, "webclient")
      controller_a = File.join(module_a, "src/main/kotlin/com/example/demo/PostController.kt")
      controller_b = File.join(module_b, "src/main/kotlin/com/example/demo/PostController.kt")

      begin
        Dir.mkdir_p(File.dirname(controller_a))
        Dir.mkdir_p(File.dirname(controller_b))
        File.write(File.join(module_a, "pom.xml"), "<project></project>")
        File.write(File.join(module_b, "pom.xml"), "<project></project>")
        File.write(controller_a, "class PostController")
        File.write(controller_b, "class PostController")

        endpoint_a = Endpoint.new("/posts", "GET", Details.new(PathInfo.new(controller_a, 12)))
        endpoint_b = Endpoint.new("/posts", "GET", Details.new(PathInfo.new(controller_b, 18)))
        endpoint_a.details.technology = "kotlin_spring"
        endpoint_b.details.technology = "kotlin_spring"
        endpoint_a.push_callee(Callee.new("postRepository.findAll", path: controller_a, line: 13))
        endpoint_b.push_callee(Callee.new("client.get", path: controller_b, line: 19))

        result = optimizer.optimize_endpoints([endpoint_a, endpoint_b])

        result.size.should eq(2)
        result.map(&.details.code_paths.size).should eq([1, 1])
        result.flat_map(&.callees.map(&.name)).sort!.should eq(["client.get", "postRepository.findAll"])
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end

    it "keeps multi-module endpoints distinct even when a collection shares the path" do
      # Regression: a collection sharing the path adds a second technology, which
      # previously neutralized the build-module scope for every endpoint at that
      # path and collapsed the two distinct module endpoints into one.
      optimizer = EndpointOptimizer.new(logger, options)
      temp_dir = File.join(Dir.tempdir, "noir-optimizer-3way-#{Process.pid}-#{Time.utc.to_unix_ms}")
      module_a = File.join(temp_dir, "data-r2dbc")
      module_b = File.join(temp_dir, "webclient")
      controller_a = File.join(module_a, "src/main/kotlin/com/example/PostController.kt")
      controller_b = File.join(module_b, "src/main/kotlin/com/example/PostController.kt")
      collection_path = File.join(temp_dir, "insomnia.yml")

      begin
        Dir.mkdir_p(File.dirname(controller_a))
        Dir.mkdir_p(File.dirname(controller_b))
        File.write(File.join(module_a, "pom.xml"), "<project></project>")
        File.write(File.join(module_b, "pom.xml"), "<project></project>")
        File.write(controller_a, "class PostController")
        File.write(controller_b, "class PostController")
        File.write(collection_path, "_type: export")

        endpoint_a = Endpoint.new("/posts", "GET", Details.new(PathInfo.new(controller_a, 12)))
        endpoint_b = Endpoint.new("/posts", "GET", Details.new(PathInfo.new(controller_b, 18)))
        endpoint_a.details.technology = "kotlin_spring"
        endpoint_b.details.technology = "kotlin_spring"

        collection_details = Details.new(PathInfo.new(collection_path, 1))
        collection_details.technology = "insomnia"
        collection_endpoint = Endpoint.new("/posts", "GET", [] of Param, collection_details)

        result = optimizer.optimize_endpoints([collection_endpoint, endpoint_a, endpoint_b])

        kotlin_results = result.select { |endpoint| endpoint.details.technology == "kotlin_spring" }
        kotlin_results.size.should eq(2)
        kotlin_results.flat_map(&.details.code_paths.map(&.path)).sort!.should eq([controller_a, controller_b].sort!)
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end

    it "merges duplicated Kotlin Spring static assets from separate build modules" do
      optimizer = EndpointOptimizer.new(logger, options)
      temp_dir = File.join(Dir.tempdir, "noir-optimizer-static-modules-#{Process.pid}-#{Time.utc.to_unix_ms}")
      module_a = File.join(temp_dir, "webflux")
      module_b = File.join(temp_dir, "r2dbc")
      static_a = File.join(module_a, "src/main/resources/static/css/style.css")
      static_b = File.join(module_b, "src/main/resources/static/css/style.css")

      begin
        Dir.mkdir_p(File.dirname(static_a))
        Dir.mkdir_p(File.dirname(static_b))
        File.write(File.join(module_a, "build.gradle.kts"), "plugins {}")
        File.write(File.join(module_b, "build.gradle.kts"), "plugins {}")
        File.write(static_a, "body{}")
        File.write(static_b, "body{}")

        endpoint_a = Endpoint.new("/css/style.css", "GET", Details.new(PathInfo.new(static_a)))
        endpoint_b = Endpoint.new("/css/style.css", "GET", Details.new(PathInfo.new(static_b)))
        endpoint_a.details.technology = "kotlin_spring"
        endpoint_b.details.technology = "kotlin_spring"

        result = optimizer.optimize_endpoints([endpoint_a, endpoint_b])

        result.size.should eq(1)
        result[0].details.code_paths.map(&.path).should eq([static_a, static_b])
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end

    it "still merges a scoped Kotlin Spring endpoint with the same endpoint from a collection" do
      optimizer = EndpointOptimizer.new(logger, options)
      temp_dir = File.join(Dir.tempdir, "noir-optimizer-cross-tech-#{Process.pid}-#{Time.utc.to_unix_ms}")
      module_dir = File.join(temp_dir, "api")
      controller_path = File.join(module_dir, "src/main/kotlin/com/example/TagController.kt")
      collection_path = File.join(temp_dir, "insomnia.yml")

      begin
        Dir.mkdir_p(File.dirname(controller_path))
        File.write(File.join(module_dir, "pom.xml"), "<project></project>")
        File.write(controller_path, "class TagController")
        File.write(collection_path, "_type: export")

        kotlin_endpoint = Endpoint.new(
          "/v1/tags", "GET", [Param.new("limit", "", "query")],
          Details.new(PathInfo.new(controller_path, 10))
        )
        kotlin_endpoint.details.technology = "kotlin_spring"
        kotlin_endpoint.push_callee(Callee.new("tagService.list", path: controller_path, line: 11))

        collection_details = Details.new(PathInfo.new(collection_path, 1))
        collection_details.technology = "insomnia"
        collection_endpoint = Endpoint.new(
          "/v1/tags", "GET", [Param.new("User-Agent", "", "header")],
          collection_details
        )

        result = optimizer.optimize_endpoints([collection_endpoint, kotlin_endpoint])

        result.size.should eq(1)
        result[0].params.map { |param| "#{param.name}:#{param.param_type}" }.sort!.should eq(["limit:query"])
        result[0].callees.map(&.name).should eq(["tagService.list"])
        result[0].details.code_paths.map(&.path).should eq([controller_path, collection_path])
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end

    it "does not leak code paths across OAS endpoints that reused Details" do
      optimizer = EndpointOptimizer.new(logger, options)

      oas_details = Details.new(PathInfo.new("openapi.json", 1))
      oas_details.technology = "oas3"
      oas_tags = Endpoint.new("/api/tags", "GET", oas_details)
      oas_users = Endpoint.new("/api/users", "POST", oas_details)

      tags_details = Details.new(PathInfo.new("tags.py", 12))
      tags_details.technology = "python_litestar"
      tags_endpoint = Endpoint.new("/api/tags", "GET", tags_details)

      users_details = Details.new(PathInfo.new("users.py", 24))
      users_details.technology = "python_litestar"
      users_endpoint = Endpoint.new("/api/users", "POST", users_details)

      result = optimizer.optimize_endpoints([oas_tags, oas_users, tags_endpoint, users_endpoint])

      result.size.should eq(2)
      tags = result.find! { |endpoint| endpoint.url == "/api/tags" }
      users = result.find! { |endpoint| endpoint.url == "/api/users" }

      tags.details.code_paths.map(&.path).should eq(["openapi.json", "tags.py"])
      users.details.code_paths.map(&.path).should eq(["openapi.json", "users.py"])
    end

    it "merges Postman colon path templates with Kotlin Spring brace templates" do
      optimizer = EndpointOptimizer.new(logger, options)
      temp_dir = File.join(Dir.tempdir, "noir-optimizer-postman-colon-#{Process.pid}-#{Time.utc.to_unix_ms}")
      module_dir = File.join(temp_dir, "api")
      controller_path = File.join(module_dir, "src/main/kotlin/com/example/ArticleController.kt")
      collection_path = File.join(temp_dir, "postman.json")

      begin
        Dir.mkdir_p(File.dirname(controller_path))
        File.write(File.join(module_dir, "build.gradle.kts"), "plugins {}")
        File.write(controller_path, "class ArticleController")
        File.write(collection_path, "{}")

        kotlin_endpoint = Endpoint.new(
          "/articles/{slug}", "GET", [Param.new("slug", "", "path")],
          Details.new(PathInfo.new(controller_path, 23))
        )
        kotlin_endpoint.details.technology = "kotlin_spring"
        kotlin_endpoint.push_callee(Callee.new("articleService.findBySlug", path: controller_path, line: 24))

        collection_details = Details.new(PathInfo.new(collection_path, 1))
        collection_details.technology = "postman"
        collection_endpoint = Endpoint.new("/articles/:slug", "GET", collection_details)

        result = optimizer.optimize_endpoints([kotlin_endpoint, collection_endpoint])

        result.size.should eq(1)
        result[0].url.should eq("/articles/{slug}")
        result[0].params.map { |param| "#{param.name}:#{param.param_type}" }.should eq(["slug:path"])
        result[0].callees.map(&.name).should eq(["articleService.findBySlug"])
        result[0].details.code_paths.map(&.path).should eq([controller_path, collection_path])
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end

    it "promotes source context when a collection duplicate is seen before Kotlin Spring" do
      optimizer = EndpointOptimizer.new(logger, options)
      controller_path = "TagController.kt"
      collection_path = "insomnia.json"

      collection_details = Details.new(PathInfo.new(collection_path, 1))
      collection_details.technology = "insomnia"
      collection_endpoint = Endpoint.new(
        "/v1/tags", "GET", [Param.new("User-Agent", "", "header")],
        collection_details
      )

      kotlin_details = Details.new(PathInfo.new(controller_path, 27))
      kotlin_details.technology = "kotlin_spring"
      kotlin_endpoint = Endpoint.new(
        "/v1/tags", "GET", [Param.new("limit", "", "query")],
        kotlin_details
      )
      kotlin_endpoint.push_callee(Callee.new("tagService.findWithPagination", path: controller_path, line: 28))

      result = optimizer.optimize_endpoints([collection_endpoint, kotlin_endpoint])

      result.size.should eq(1)
      result[0].details.technology.should eq("kotlin_spring")
      result[0].details.code_paths.map(&.path).should eq([controller_path, collection_path])
      result[0].callees.map(&.name).should eq(["tagService.findWithPagination"])
      result[0].params.map { |param| "#{param.name}:#{param.param_type}" }.sort!.should eq(["limit:query"])
    end

    it "keeps meaningful collection headers when merging with source endpoints" do
      optimizer = EndpointOptimizer.new(logger, options)
      controller_path = "TagController.kt"
      collection_path = "postman.json"

      kotlin_details = Details.new(PathInfo.new(controller_path, 27))
      kotlin_details.technology = "kotlin_spring"
      kotlin_endpoint = Endpoint.new(
        "/v1/tags", "GET", [Param.new("limit", "", "query")],
        kotlin_details
      )

      collection_details = Details.new(PathInfo.new(collection_path, 1))
      collection_details.technology = "postman"
      collection_endpoint = Endpoint.new(
        "/v1/tags", "GET", [
        Param.new("User-Agent", "PostmanRuntime", "header"),
        Param.new("Authorization", "Bearer token", "header"),
        Param.new("X-Tenant", "demo", "header"),
      ],
        collection_details
      )

      result = optimizer.optimize_endpoints([kotlin_endpoint, collection_endpoint])

      result.size.should eq(1)
      result[0].params.map { |param| "#{param.name}:#{param.param_type}" }.sort!.should eq([
        "Authorization:header",
        "X-Tenant:header",
        "limit:query",
      ])
    end

    it "drops body-less collection GraphQL transport placeholders when operation endpoints exist" do
      optimizer = EndpointOptimizer.new(logger, options)
      collection_details = Details.new(PathInfo.new("insomnia.json", 1))
      collection_details.technology = "insomnia"
      transport = Endpoint.new(
        "/graphql", "POST", [Param.new("User-Agent", "insomnia/8.5.1", "header")],
        collection_details
      )

      operation_details = Details.new(PathInfo.new("schema.graphqls", 2))
      operation_details.technology = "graphql_sdl"
      operation = Endpoint.new(
        "/graphql#Query.books", "POST",
        [Param.new("graphql_query_books", "query { books }", "json")],
        operation_details
      )
      operation.add_tag(Tag.new("graphql", "Query.books", "graphql_sdl_analyzer"))

      result = optimizer.optimize_endpoints([transport, operation])

      result.map(&.url).should eq(["/graphql#Query.books"])
    end

    it "keeps collection GraphQL transport endpoints with meaningful body or auth context" do
      optimizer = EndpointOptimizer.new(logger, options)
      body_details = Details.new(PathInfo.new("insomnia.json", 1))
      body_details.technology = "insomnia"
      body_transport = Endpoint.new(
        "/graphql", "POST", [Param.new("query", "query { books }", "json")],
        body_details
      )

      auth_details = Details.new(PathInfo.new("postman.json", 1))
      auth_details.technology = "postman"
      auth_transport = Endpoint.new(
        "/api/graphql", "POST", [Param.new("Authorization", "Bearer token", "header")],
        auth_details
      )

      operation_details = Details.new(PathInfo.new("schema.graphqls", 2))
      operation_details.technology = "graphql_sdl"
      operation = Endpoint.new(
        "/graphql#Query.books", "POST",
        [Param.new("graphql_query_books", "query { books }", "json")],
        operation_details
      )

      api_operation_details = Details.new(PathInfo.new("ArticleController.kt", 12))
      api_operation_details.technology = "kotlin_spring"
      api_operation = Endpoint.new(
        "/api/graphql#Query.article", "POST",
        [Param.new("graphql_query_article", "query { article }", "json")],
        api_operation_details
      )

      result = optimizer.optimize_endpoints([body_transport, auth_transport, operation, api_operation])

      result.map(&.url).sort!.should eq([
        "/api/graphql",
        "/api/graphql#Query.article",
        "/graphql",
        "/graphql#Query.books",
      ])
    end

    it "merges collection concrete examples into Kotlin Spring templates without swallowing static routes" do
      optimizer = EndpointOptimizer.new(logger, options)
      controller_path = "TagController.kt"
      collection_path = "insomnia.json"

      template_endpoint = Endpoint.new(
        "/v1/tags/{id}", "GET", [Param.new("id", "", "path")],
        Details.new(PathInfo.new(controller_path, 30))
      )
      template_endpoint.details.technology = "kotlin_spring"
      template_endpoint.push_callee(Callee.new("tagService.findById", path: controller_path, line: 31))

      count_endpoint = Endpoint.new(
        "/v1/tags/count", "GET", [] of Param,
        Details.new(PathInfo.new(controller_path, 20))
      )
      count_endpoint.details.technology = "kotlin_spring"

      example_details = Details.new(PathInfo.new(collection_path, 1))
      example_details.technology = "insomnia"
      example_endpoint = Endpoint.new(
        "/v1/tags/1", "GET", [Param.new("User-Agent", "", "header")],
        example_details
      )

      count_collection_details = Details.new(PathInfo.new(collection_path, 2))
      count_collection_details.technology = "insomnia"
      count_collection_endpoint = Endpoint.new(
        "/v1/tags/count", "GET", [Param.new("User-Agent", "", "header")],
        count_collection_details
      )

      result = optimizer.optimize_endpoints([
        example_endpoint,
        count_collection_endpoint,
        template_endpoint,
        count_endpoint,
      ])

      result.map(&.url).sort!.should eq(["/v1/tags/count", "/v1/tags/{id}"])
      template = result.find! { |endpoint| endpoint.url == "/v1/tags/{id}" }
      template.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!.should eq(["id:path"])
      template.callees.map(&.name).should eq(["tagService.findById"])
      template.details.code_paths.map(&.path).should eq([controller_path, collection_path])

      count = result.find! { |endpoint| endpoint.url == "/v1/tags/count" }
      count.details.technology.should eq("kotlin_spring")
      count.details.code_paths.map(&.path).should eq([controller_path, collection_path])
    end

    it "merges collection examples that contain Postman path variables into source templates" do
      optimizer = EndpointOptimizer.new(logger, options)
      controller_path = "ProfileController.kt"
      collection_path = "postman.json"

      template_endpoint = Endpoint.new(
        "/profiles/{username}", "GET", [Param.new("username", "", "path")],
        Details.new(PathInfo.new(controller_path, 12))
      )
      template_endpoint.details.technology = "kotlin_spring"
      template_endpoint.push_callee(Callee.new("profileService.find", path: controller_path, line: 13))

      collection_details = Details.new(PathInfo.new(collection_path, 1))
      collection_details.technology = "postman"
      example_endpoint = Endpoint.new("/profiles/celeb_:USERNAME", "GET", collection_details)

      result = optimizer.optimize_endpoints([example_endpoint, template_endpoint])

      result.size.should eq(1)
      result[0].url.should eq("/profiles/{username}")
      result[0].params.map { |param| "#{param.name}:#{param.param_type}" }.should eq(["username:path"])
      result[0].callees.map(&.name).should eq(["profileService.find"])
      result[0].details.code_paths.map(&.path).should eq([controller_path, collection_path])
    end

    it "prefers GraphQL SDL argument names while keeping Kotlin Spring context" do
      optimizer = EndpointOptimizer.new(logger, options)
      content_param = Param.new("content", "", "json")
      content_param.add_tag(Tag.new("graphql-input-field", "input", "kotlin_spring_graphql_analyzer"))
      user_id_param = Param.new("userId", "", "json")
      user_id_param.add_tag(Tag.new("graphql-input-field", "input", "kotlin_spring_graphql_analyzer"))
      kotlin_params = [
        Param.new("id", "", "json"),
        content_param,
        user_id_param,
        Param.new("graphql_mutation_addComment", "mutation($id: String, $input: AddCommentInput) { addComment(id: $id, input: $input) }", "json"),
      ]
      kotlin_endpoint = Endpoint.new(
        "/graphql#Mutation.addComment", "POST", kotlin_params,
        Details.new(PathInfo.new("ArticleController.kt", 39))
      )
      kotlin_endpoint.add_tag(Tag.new("graphql", "Mutation.addComment", "kotlin_spring_graphql_analyzer"))
      kotlin_endpoint.push_callee(Callee.new("articleService.addComment", path: "ArticleController.kt", line: 44))

      sdl_params = [
        Param.new("articleId", "", "json"),
        Param.new("input", "", "json"),
        Param.new("graphql_mutation_addComment", "mutation($articleId: ID!, $input: AddCommentInput!) { addComment(articleId: $articleId, input: $input) }", "json"),
      ]
      sdl_details = Details.new(PathInfo.new("schema.graphqls", 8))
      sdl_details.technology = "graphql_sdl"
      sdl_endpoint = Endpoint.new(
        "/graphql#Mutation.addComment", "POST", sdl_params,
        sdl_details
      )
      sdl_endpoint.add_tag(Tag.new("graphql", "Mutation.addComment", "graphql_sdl_analyzer"))

      result = optimizer.optimize_endpoints([kotlin_endpoint, sdl_endpoint])

      result.size.should eq(1)
      result[0].params.map(&.name).should eq(["content", "userId", "graphql_mutation_addComment", "articleId"])
      result[0].params.find { |param| param.name == "id" }.should be_nil
      result[0].params.find { |param| param.name == "input" }.should be_nil
      doc_param = result[0].params.find { |param| param.name == "graphql_mutation_addComment" }
      doc_param.should_not be_nil
      doc_param.not_nil!.value.should contain("articleId")
      result[0].tags.map { |tag| "#{tag.name}:#{tag.description}:#{tag.tagger}" }.should eq([
        "graphql:Mutation.addComment:graphql_sdl_analyzer",
      ])
      result[0].callees.map(&.name).should eq(["articleService.addComment"])
      result[0].details.code_paths.map(&.path).should eq(["ArticleController.kt", "schema.graphqls"])
    end

    it "still merges Kotlin Spring GraphQL endpoints with SDL when the controller is under a build module" do
      optimizer = EndpointOptimizer.new(logger, options)
      temp_dir = File.join(Dir.tempdir, "noir-optimizer-graphql-#{Process.pid}-#{Time.utc.to_unix_ms}")
      module_dir = File.join(temp_dir, "graphql-app")
      controller_path = File.join(module_dir, "src/main/kotlin/com/example/ArticleController.kt")
      schema_path = File.join(temp_dir, "schema.graphqls")

      begin
        Dir.mkdir_p(File.dirname(controller_path))
        File.write(File.join(module_dir, "pom.xml"), "<project></project>")
        File.write(controller_path, "class ArticleController")
        File.write(schema_path, "type Query { article(id: ID!): Article }")

        kotlin_endpoint = Endpoint.new(
          "/graphql#Query.article", "POST",
          [Param.new("graphql_query_article", "query($id: ID!) { article(id: $id) }", "json")],
          Details.new(PathInfo.new(controller_path, 12))
        )
        kotlin_endpoint.details.technology = "kotlin_spring"
        kotlin_endpoint.add_tag(Tag.new("graphql", "Query.article", "kotlin_spring_graphql_analyzer"))
        kotlin_endpoint.push_callee(Callee.new("articleService.findArticle", path: controller_path, line: 13))

        sdl_details = Details.new(PathInfo.new(schema_path, 1))
        sdl_details.technology = "graphql_sdl"
        sdl_endpoint = Endpoint.new(
          "/graphql#Query.article", "POST",
          [Param.new("id", "", "json"), Param.new("graphql_query_article", "query($id: ID!) { article(id: $id) }", "json")],
          sdl_details
        )
        sdl_endpoint.add_tag(Tag.new("graphql", "Query.article", "graphql_sdl_analyzer"))

        result = optimizer.optimize_endpoints([kotlin_endpoint, sdl_endpoint])

        result.size.should eq(1)
        result[0].params.map(&.name).should eq(["graphql_query_article", "id"])
        result[0].callees.map(&.name).should eq(["articleService.findArticle"])
        result[0].details.code_paths.map(&.path).should eq([controller_path, schema_path])
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end

    it "normalizes URLs with slashes" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("api/users", "GET"),   # missing leading slash
        Endpoint.new("//api//data", "GET"), # double slashes
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].url.should eq("/api/users")
      result[1].url.should eq("/api/data")
    end

    it "does not corrupt absolute URLs while normalizing slashes" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("https://api.example.com/v1/users", "GET"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].url.should eq("https://api.example.com/v1/users")
    end

    it "collapses path slashes without touching an embedded URL in the query" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        # The double slash in `https://` inside the query value must
        # survive; only the redundant `//` in the path is collapsed.
        Endpoint.new("//auth//callback?redirect_uri=https://app.example/cb", "GET"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].url.should eq("/auth/callback?redirect_uri=https://app.example/cb")
    end

    it "strips Spring inline regex constraints from path variables" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/users/{id:[0-9]+}", "GET"),
        Endpoint.new("/files/{path:.*}", "GET"),
        Endpoint.new("/a/{x:[^/]+}/b/{y}", "GET"),
      ]

      result = optimizer.normalize_url_shapes(endpoints)
      result[0].url.should eq("/users/{id}")
      result[1].url.should eq("/files/{path}")
      result[2].url.should eq("/a/{x}/b/{y}")
    end

    it "normalizes Django re_path named groups even when the body contains \\d / \\w classes" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/(?P<organization_slug>[^/]+)/issues/(?P<group_id>\\d+)/", "GET"),
        Endpoint.new("/api/0/(?P<event_id>[A-Fa-f0-9-]{32,36})/", "GET"),
      ]

      result = optimizer.normalize_url_shapes(endpoints)
      result[0].url.should eq("/{organization_slug}/issues/{group_id}/")
      result[1].url.should eq("/api/0/{event_id}/")
    end

    it "still skips verbatim Express regex-literal routes" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/^\\/api\\/(\\d+)$/", "GET"),
      ]

      result = optimizer.normalize_url_shapes(endpoints)
      result[0].url.should eq("/^\\/api\\/(\\d+)$/")
    end
  end

  describe "combine_url_and_endpoints" do
    it "combines target URL with endpoints" do
      options["url"] = YAML::Any.new("https://example.com")
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/api/users", "GET"),
        Endpoint.new("api/data", "POST"),
      ]

      result = optimizer.combine_url_and_endpoints(endpoints)
      result[0].url.should eq("https://example.com/api/users")
      result[1].url.should eq("https://example.com/api/data")
    end

    it "returns unchanged endpoints when no target URL" do
      options["url"] = YAML::Any.new("")
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/api/users", "GET"),
      ]

      result = optimizer.combine_url_and_endpoints(endpoints)
      result[0].url.should eq("/api/users")
    end

    it "strips the target only as a leading prefix, not inside query values" do
      options["url"] = YAML::Any.new("https://example.com")
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        # The target host appears in a query value, not as a prefix — a
        # blanket gsub would drop it and corrupt the redirect target.
        Endpoint.new("/proxy?next=https://example.com/login", "GET"),
        # Already-prefixed endpoint should be de-duplicated to a single prefix.
        Endpoint.new("https://example.com/api/users", "GET"),
      ]

      result = optimizer.combine_url_and_endpoints(endpoints)
      result[0].url.should eq("https://example.com/proxy?next=https://example.com/login")
      result[1].url.should eq("https://example.com/api/users")
    end

    it "passes through absolute endpoint URLs on a different host" do
      options["url"] = YAML::Any.new("https://example.com")
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("https://cdn.other.com/assets/app.js", "GET"),
      ]

      result = optimizer.combine_url_and_endpoints(endpoints)
      # The scheme `//` must survive (no collapse) and the target must
      # not be prepended onto a self-contained absolute URL.
      result[0].url.should eq("https://cdn.other.com/assets/app.js")
    end
  end

  describe "add_path_parameters" do
    it "extracts parameters from curly brace patterns" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/users/{id}", "GET"),
        Endpoint.new("/posts/{id}/comments/{comment_id}", "GET"),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("id")
      result[0].params[0].param_type.should eq("path")

      result[1].params.size.should eq(2)
      result[1].params[0].name.should eq("id")
      result[1].params[1].name.should eq("comment_id")
    end

    it "extracts every variable from a comma-packed segment" do
      optimizer = EndpointOptimizer.new(logger, options)
      # Spring's matrix-style mapping packs sibling path variables into one
      # segment separated by commas (e.g.
      # @GetMapping("/bbox/{xMin},{yMin},{xMax},{yMax}")). Each is a path
      # param; only the first used to be captured.
      endpoints = [
        Endpoint.new("/bbox/{xMin},{yMin},{xMax},{yMax}", "GET"),
        Endpoint.new("/user/{userName}/location/{x},{y}", "PUT"),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.map(&.name).should eq(["xMin", "yMin", "xMax", "yMax"])
      result[0].params.all? { |p| p.param_type == "path" }.should be_true
      result[1].params.map(&.name).should eq(["userName", "x", "y"])
    end

    it "does not treat regex quantifiers as curly brace path params" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/archive/\\d{4}/", "GET"),
        Endpoint.new("/archive/{year}/", "GET"),
      ]

      result = optimizer.add_path_parameters(endpoints)

      result[0].params.should be_empty
      result[1].params.map(&.name).should eq(["year"])
    end

    it "extracts parameters from colon patterns" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/users/:id", "GET"),
        Endpoint.new("/posts/:post_id/edit", "GET"),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("id")

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("post_id")
    end

    it "strips colon path parameter suffixes from the parameter name" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/geo/:ip?", "GET"),          # Fiber / Express optional segment
        Endpoint.new("/users/:id(\\d+)", "GET"),   # Express regex-constrained segment
        Endpoint.new("/assets/:file.json", "GET"), # Play/format suffix
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.map(&.name).should eq(["ip"])
      result[1].params.map(&.name).should eq(["id"])
      result[2].params.map(&.name).should eq(["file"])
    end

    it "does not duplicate a path param the analyzer already recorded with a type" do
      optimizer = EndpointOptimizer.new(logger, options)
      # Haskell's Servant/Yesod analyzers store the captured type in the param
      # `value` (e.g. `Capture "id" Int`). The URL-derived param has an empty
      # value, so an exact-struct dedup used to miss it and add a duplicate.
      endpoints = [
        Endpoint.new("/users/:id", "GET", [Param.new("id", "Int", "path")]),
        Endpoint.new("/sites/{site_id}", "GET", [Param.new("site_id", "SiteId", "path")]),
        Endpoint.new("/files/*path", "GET", [Param.new("path", "Text", "path")]),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result.each do |endpoint|
        path_params = endpoint.params.select { |param| param.param_type == "path" }
        path_params.size.should eq(1)
        # The analyzer-supplied type must survive (no empty-value clobber).
        path_params[0].value.should_not eq("")
      end
    end

    it "reconciles ruby path params against same-named query/body params" do
      optimizer = EndpointOptimizer.new(logger, options)
      ruby_details = Details.new
      ruby_details.technology = "ruby_rails"
      other_details = Details.new
      other_details.technology = "lucky"

      endpoints = [
        # Rack frameworks merge path captures into params, so the body
        # `params[:id]` for /users/:id IS the path value — drop the query dup.
        Endpoint.new("/users/:id", "GET", [Param.new("id", "", "query"), Param.new("token", "", "query")], ruby_details),
        # Non-ruby (Lucky) keeps separate typed path/query buckets — keep both.
        Endpoint.new("/users/:id", "GET", [Param.new("id", "", "query")], other_details),
      ]

      result = optimizer.add_path_parameters(endpoints)

      ruby_params = result[0].params
      ruby_params.count { |p| p.name == "id" }.should eq(1)
      ruby_params.find! { |p| p.name == "id" }.param_type.should eq("path")
      ruby_params.any? { |p| p.name == "token" && p.param_type == "query" }.should be_true

      result[1].params.count { |p| p.name == "id" }.should eq(2) # path + query both kept
    end

    it "names catch-all path variables without the leading asterisk" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/files/{*path}", "GET"), # Spring / Armeria / ASP.NET
        Endpoint.new("/static/{*remaining}/raw", "GET"),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("path")
      result[0].params[0].param_type.should eq("path")

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("remaining")
    end

    it "ignores bare glob splats that are not real parameter names" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/glob/**", "GET"),      # Armeria glob: captures `*`, not a name
        Endpoint.new("/assets/*file", "GET"), # named splat is still a parameter
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(0)

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("file")
      result[1].params[0].param_type.should eq("path")
    end

    it "extracts parameters from angle bracket patterns" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/users/<id>", "GET"),
        Endpoint.new("/posts/<int:post_id>", "GET"), # Django style
        Endpoint.new("/items/<name:str>", "GET"),    # Marten style
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("id")

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("post_id")

      result[2].params.size.should eq(1)
      result[2].params[0].name.should eq("name")
    end
  end

  describe "apply_pvalue" do
    it "applies configured parameter values" do
      options["set_pvalue"] = YAML::Any.new([YAML::Any.new("name=FUZZ")])
      optimizer = EndpointOptimizer.new(logger, options)

      result = optimizer.apply_pvalue("query", "name", "original")
      result.should eq("FUZZ")
    end

    it "returns original value when no configuration matches" do
      options["set_pvalue"] = YAML::Any.new([] of YAML::Any)
      optimizer = EndpointOptimizer.new(logger, options)

      result = optimizer.apply_pvalue("query", "unknown", "original")
      result.should eq("original")
    end
  end

  describe "full optimization workflow" do
    it "runs complete optimization pipeline" do
      options["url"] = YAML::Any.new("https://api.example.com")
      options["set_pvalue"] = YAML::Any.new([YAML::Any.new("id=123")])
      optimizer = EndpointOptimizer.new(logger, options)

      endpoints = [
        Endpoint.new("/users/{id}", "GET"),
        Endpoint.new("users/{id}", "GET"), # duplicate with different slash
        Endpoint.new("/posts/:post_id", "POST"),
      ]

      result = optimizer.optimize(endpoints)

      # Should have 2 unique endpoints after deduplication
      result.size.should eq(2)

      # URLs should be combined with target URL
      result[0].url.should contain("https://api.example.com")
      result[1].url.should contain("https://api.example.com")

      # Parameters should be extracted
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("id")
      result[0].params[0].param_type.should eq("path")

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("post_id")
      result[1].params[0].param_type.should eq("path")
    end
  end
end
