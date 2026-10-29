require "file_utils"
require "../../spec_helper"
require "../../../src/optimizer/optimizer"
require "../../../src/models/endpoint"
require "../../../src/models/logger"

private def coded_endpoint(url : String, method : String, technology : String, path : String, line : Int32, param_name : String? = nil) : Endpoint
  params = param_name ? [Param.new(param_name, "", "json")] : [] of Param
  details = Details.new(PathInfo.new(path, line))
  details.technology = technology
  Endpoint.new(url, method, params, details)
end

private def service_routes(technology : String, orders_app : String, users_app : String) : Array(Endpoint)
  [
    coded_endpoint("/health", "GET", technology, orders_app, 1),
    coded_endpoint("/items", "POST", technology, orders_app, 2, "orders_name"),
    coded_endpoint("/health", "GET", technology, users_app, 1),
    coded_endpoint("/items", "POST", technology, users_app, 2, "users_name"),
  ]
end

private def route_rows(result : Array(Endpoint))
  result.map do |endpoint|
    {
      endpoint.method,
      endpoint.url,
      endpoint.details.code_paths.map(&.path),
      endpoint.params.map(&.name),
    }
  end
end

private def separate_rows(orders_app : String, users_app : String)
  [
    {"GET", "/health", [orders_app], [] of String},
    {"POST", "/items", [orders_app], ["orders_name"]},
    {"GET", "/health", [users_app], [] of String},
    {"POST", "/items", [users_app], ["users_name"]},
  ]
end

private def merged_rows(orders_app : String, users_app : String)
  [
    {"GET", "/health", [orders_app, users_app], [] of String},
    {"POST", "/items", [orders_app, users_app], ["orders_name", "users_name"]},
  ]
end

private def write_file(path : String, body : String) : Nil
  Dir.mkdir_p(File.dirname(path))
  File.write(path, body)
end

private def with_root(prefix : String, &)
  root = File.tempname(prefix)
  Dir.mkdir_p(root)
  begin
    yield root
  ensure
    FileUtils.rm_rf(root)
  end
end

describe "EndpointOptimizer project manifests" do
  options = create_test_options
  logger = NoirLogger.new(false, false, false, true)

  describe "optimize_endpoints" do
    {"requirements.txt", "setup.py", "setup.cfg", "Pipfile"}.each do |manifest|
      it "keeps two services that each ship #{manifest} distinct" do
        optimizer = EndpointOptimizer.new(logger, options)
        with_root("noir-py-manifest-") do |root|
          orders_app = File.join(root, "services/orders/app.py")
          users_app = File.join(root, "services/users/app.py")
          write_file(orders_app, "orders")
          write_file(users_app, "users")
          write_file(File.join(root, "services/orders", manifest), "orders\n")
          write_file(File.join(root, "services/users", manifest), "users\n")

          result = optimizer.optimize_endpoints(service_routes("python_flask", orders_app, users_app))
          route_rows(result).should eq(separate_rows(orders_app, users_app))
        end
      end
    end

    {"requirements-dev.txt", "requirements-prod.txt", "Pipfile.lock"}.each do |manifest|
      it "merges two services when the only manifest-like file is #{manifest}" do
        optimizer = EndpointOptimizer.new(logger, options)
        with_root("noir-py-not-manifest-") do |root|
          orders_app = File.join(root, "services/orders/app.py")
          users_app = File.join(root, "services/users/app.py")
          write_file(orders_app, "orders")
          write_file(users_app, "users")
          write_file(File.join(root, "services/orders", manifest), "orders\n")
          write_file(File.join(root, "services/users", manifest), "users\n")

          result = optimizer.optimize_endpoints(service_routes("python_flask", orders_app, users_app))
          route_rows(result).should eq(merged_rows(orders_app, users_app))
        end
      end
    end

    it "merges the same routes when no project manifest exists" do
      optimizer = EndpointOptimizer.new(logger, options)
      with_root("noir-no-manifest-") do |root|
        orders_app = File.join(root, "services/orders/app.py")
        users_app = File.join(root, "services/users/app.py")
        write_file(orders_app, "orders")
        write_file(users_app, "users")

        result = optimizer.optimize_endpoints(service_routes("python_flask", orders_app, users_app))
        route_rows(result).should eq(merged_rows(orders_app, users_app))
      end
    end

    it "scopes a nested requirements.txt closer than a parent pyproject.toml" do
      optimizer = EndpointOptimizer.new(logger, options)
      with_root("noir-py-nearest-") do |root|
        orders_app = File.join(root, "services/orders/app.py")
        users_app = File.join(root, "services/users/app.py")
        write_file(File.join(root, "pyproject.toml"), "[project]\nname = \"mono\"\n")
        write_file(orders_app, "orders")
        write_file(users_app, "users")
        write_file(File.join(root, "services/orders/requirements.txt"), "flask\n")

        result = optimizer.optimize_endpoints(service_routes("python_flask", orders_app, users_app))
        route_rows(result).should eq(separate_rows(orders_app, users_app))
      end
    end

    it "keeps one scope when pyproject.toml and requirements.txt share a directory" do
      optimizer = EndpointOptimizer.new(logger, options)
      with_root("noir-py-same-dir-") do |root|
        orders_app = File.join(root, "orders/app.py")
        users_app = File.join(root, "users/app.py")
        write_file(File.join(root, "pyproject.toml"), "[project]\nname = \"svc\"\n")
        write_file(File.join(root, "requirements.txt"), "flask\n")
        write_file(orders_app, "orders")
        write_file(users_app, "users")

        result = optimizer.optimize_endpoints(service_routes("python_flask", orders_app, users_app))
        route_rows(result).should eq(merged_rows(orders_app, users_app))
      end
    end

    it "keeps sibling Bazel binaries distinct and a nested java_library in the binary scope" do
      optimizer = EndpointOptimizer.new(logger, options)
      with_root("noir-bazel-binary-") do |root|
        orders_app = File.join(root, "services/orders/App.java")
        orders_lib = File.join(root, "services/orders/lib/Extra.java")
        users_app = File.join(root, "services/users/App.java")
        write_file(File.join(root, "WORKSPACE"), "workspace(name = \"ws\")\n")
        write_file(File.join(root, "MODULE.bazel"), "module(name = \"ws\")\n")
        write_file(File.join(root, "services/orders/BUILD.bazel"), "java_binary (\n    name = \"orders\",\n)\n")
        write_file(File.join(root, "services/orders/lib/BUILD"), "java_library(\n    name = \"lib\",\n)\n")
        write_file(File.join(root, "services/users/BUILD.bazel"), "py_binary(\n    name = \"users\",\n)\n")
        write_file(orders_app, "class App {}")
        write_file(orders_lib, "class Extra {}")
        write_file(users_app, "class App {}")

        endpoints = service_routes("java_spring", orders_app, users_app)
        endpoints << coded_endpoint("/health", "GET", "java_spring", orders_lib, 4)

        result = optimizer.optimize_endpoints(endpoints)
        route_rows(result).should eq([
          {"GET", "/health", [orders_app, orders_lib], [] of String},
          {"POST", "/items", [orders_app], ["orders_name"]},
          {"GET", "/health", [users_app], [] of String},
          {"POST", "/items", [users_app], ["users_name"]},
        ])
      end
    end

    it "does not treat java_library, WORKSPACE, or a helper call as a project boundary" do
      optimizer = EndpointOptimizer.new(logger, options)
      with_root("noir-bazel-library-") do |root|
        orders_app = File.join(root, "services/orders/App.java")
        users_app = File.join(root, "services/users/App.java")
        write_file(File.join(root, "WORKSPACE"), "workspace(name = \"ws\")\n")
        write_file(File.join(root, "MODULE.bazel"), "module(name = \"ws\")\n")
        write_file(File.join(root, "services/orders/BUILD"), "java_library(\n    name = \"orders\",\n)\nmy_binary_helper(\n    name = \"nope\",\n)\n")
        write_file(File.join(root, "services/users/BUILD.bazel"), "java_library(\n    name = \"users\",\n)\n")
        write_file(orders_app, "class App {}")
        write_file(users_app, "class App {}")

        result = optimizer.optimize_endpoints(service_routes("java_spring", orders_app, users_app))
        route_rows(result).should eq(merged_rows(orders_app, users_app))
      end
    end

    it "treats either BUILD or BUILD.bazel as enough when one invokes an image rule" do
      optimizer = EndpointOptimizer.new(logger, options)
      with_root("noir-bazel-either-") do |root|
        orders_app = File.join(root, "orders/App.java")
        users_app = File.join(root, "users/App.java")
        write_file(File.join(root, "orders/BUILD"), "java_library(\n    name = \"orders\",\n)\n")
        write_file(File.join(root, "orders/BUILD.bazel"), "oci_image(\n    name = \"orders\",\n)\n")
        write_file(File.join(root, "users/BUILD.bazel"), "java_library(\n    name = \"users\",\n)\n")
        write_file(File.join(root, "users/BUILD"), "container_image(\n    name = \"users\",\n)\n")
        write_file(orders_app, "class App {}")
        write_file(users_app, "class App {}")

        result = optimizer.optimize_endpoints(service_routes("java_spring", orders_app, users_app))
        route_rows(result).should eq(separate_rows(orders_app, users_app))
      end
    end
  end
end
