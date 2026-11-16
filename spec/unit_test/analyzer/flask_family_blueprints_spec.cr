require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

private def blueprint_urls(framework : String, sources : Hash(String, String), multiple_bases = false) : Array(String)
  root = File.tempname("noir-blueprints")
  sources.each do |name, source|
    path = File.join(root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source.gsub("FRAMEWORK", framework).gsub("APPLICATION", framework.capitalize))
  end
  options = create_test_options
  bases = multiple_bases ? [File.join(root, "a"), File.join(root, "b")] : [root]
  options["base"] = YAML::Any.new(bases.map { |base| YAML::Any.new(base) })
  options["only_techs"] = YAML::Any.new("python_#{framework}")
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.map(&.url).sort!
ensure
  CodeLocator.instance.reset_files
  FileUtils.rm_rf(root) if root && Dir.exists?(root)
end

{% for framework in ["flask", "quart"] %}
  describe "{{ framework.id }} blueprint parity" do
    it "reads multiline registrations and expression prefixes" do
      blueprint_urls({{ framework }}, {
        "app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION, Blueprint
          app = APPLICATION(__name__)
          bp = Blueprint('bp', __name__, url_prefix='/old')
          API = '/api'
          app.register_blueprint(
           bp,
           url_prefix=API + '/v1'
          )
          @bp.get('/item')
          async def item(): pass
          PYTHON
      }).should eq(["/api/v1/item"])
    end

    it "reads config prefixes and get defaults" do
      blueprint_urls({{ framework }}, {
        "app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION, Blueprint
          app = APPLICATION(__name__)
          a = Blueprint('a', __name__)
          b = Blueprint('b', __name__)
          app.register_blueprint(a, url_prefix=app.config['API'])
          app.register_blueprint(b, url_prefix=app.config.get('MISSING', '/default'))
          @a.get('/a')
          async def one(): pass
          @b.get('/b')
          async def two(): pass
          PYTHON
        "config.py" => <<-PYTHON,
          API = '/configured'
          PYTHON
      }).should eq(["/configured/a", "/default/b"])
    end

    it "resolves direct factories, assigned factories and function-local blueprints" do
      blueprint_urls({{ framework }}, {
        "app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION, Blueprint
          import views
          app = APPLICATION(__name__)
          app.register_blueprint(views.make(), url_prefix='/direct')
          def setup(app):
              alias = views.make()
              app.register_blueprint(alias, url_prefix='/assigned')
              local = Blueprint('local', __name__)
              @local.get('/local')
              async def local_view(): pass
              app.register_blueprint(local, url_prefix='/setup')
          PYTHON
        "views.py" => <<-PYTHON,
          import FRAMEWORK
          def make():
              bp = FRAMEWORK.Blueprint('bp', __name__, url_prefix='/old')
              @bp.get('/item')
              async def item(): pass
              return bp
          PYTHON
      }).should eq(["/assigned/item", "/direct/item", "/setup/local"])
    end

    it "propagates across mixed same-file and cross-file mounts under every parent" do
      blueprint_urls({{ framework }}, {
        "app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION, Blueprint
          from views import middle
          app = APPLICATION(__name__)
          outer = Blueprint('outer', __name__, url_prefix='/outer')
          outer.register_blueprint(middle)
          app.register_blueprint(outer, url_prefix='/one')
          app.register_blueprint(outer, url_prefix='/two')
          PYTHON
        "views.py" => <<-PYTHON,
          from FRAMEWORK import Blueprint
          middle = Blueprint('middle', __name__, url_prefix='/middle')
          leaf = Blueprint('leaf', __name__, url_prefix='/leaf')
          middle.register_blueprint(leaf)
          @leaf.get('/item')
          async def item(): pass
          PYTHON
      }).should eq(["/one/middle/leaf/item", "/two/middle/leaf/item"])
    end

    it "combines a direct child registration with nested mounts and empty overrides" do
      blueprint_urls({{ framework }}, {
        "app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION, Blueprint
          from views import leaf
          app = APPLICATION(__name__)
          outer = Blueprint('outer', __name__, url_prefix='/outer')
          middle = Blueprint('middle', __name__, url_prefix='/middle')
          outer.register_blueprint(middle, url_prefix='')
          middle.register_blueprint(leaf, url_prefix='')
          app.register_blueprint(outer, url_prefix='/root')
          app.register_blueprint(leaf, url_prefix='/direct')
          PYTHON
        "views.py" => <<-PYTHON,
          from FRAMEWORK import Blueprint
          leaf = Blueprint('leaf', __name__, url_prefix='/old')
          @leaf.get('/item')
          async def item(): pass
          PYTHON
      }).should eq(["/direct/item", "/root/item"])
    end

    it "keeps an imported child's direct default mount beside its nested mount" do
      blueprint_urls({{ framework }}, {
        "app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION, Blueprint
          from leaf import child
          app = APPLICATION(__name__)
          outer = Blueprint('outer', __name__, url_prefix='/outer')
          outer.register_blueprint(child)
          app.register_blueprint(outer)
          app.register_blueprint(child)
          PYTHON
        "leaf.py" => <<-PYTHON,
          from FRAMEWORK import Blueprint
          child = Blueprint('child', __name__, url_prefix='/child')
          @child.get('/item')
          async def item(): pass
          PYTHON
      }).should eq(["/child/item", "/outer/child/item"])
    end

    it "resolves an imported parent alias before propagating its mounted prefix" do
      blueprint_urls({{ framework }}, {
        "app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION
          from parent import outer as renamed
          from leaf import child
          app = APPLICATION(__name__)
          renamed.register_blueprint(child, url_prefix='/child')
          app.register_blueprint(renamed, url_prefix='/mounted')
          PYTHON
        "parent.py" => <<-PYTHON,
          from FRAMEWORK import Blueprint
          outer = Blueprint('outer', __name__, url_prefix='/outer')
          PYTHON
        "leaf.py" => <<-PYTHON,
          from FRAMEWORK import Blueprint
          child = Blueprint('child', __name__, url_prefix='/old')
          @child.get('/item')
          async def item(): pass
          PYTHON
      }).should eq(["/mounted/child/item"])
    end

    it "distinguishes an app and blueprint with the same name in different files of one base" do
      blueprint_urls({{ framework }}, {
        "a.py" => "from FRAMEWORK import APPLICATION\nshared = APPLICATION(__name__)\n",
        "b.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION, Blueprint
          from leaf import child
          app = APPLICATION(__name__)
          shared = Blueprint('shared', __name__, url_prefix='/parent')
          shared.register_blueprint(child)
          app.register_blueprint(shared, url_prefix='/mounted')
          PYTHON
        "leaf.py" => <<-PYTHON,
          from FRAMEWORK import Blueprint
          child = Blueprint('child', __name__, url_prefix='/child')
          @child.get('/item')
          async def item(): pass
          PYTHON
      }).should eq(["/mounted/child/item"])
    end

    it "resolves local blueprint aliases and keyword or tab-separated registrations" do
      ["renamed, url_prefix='/mounted'", "blueprint=renamed, url_prefix='/mounted'", "\trenamed, url_prefix='/mounted'"].each do |arguments|
        source = <<-PYTHON
          from FRAMEWORK import APPLICATION, Blueprint
          app = APPLICATION(__name__)
          bp = Blueprint('bp', __name__, url_prefix='/own')
          renamed = bp
          app.register_blueprint(#{arguments})
          @bp.get('/item')
          async def item(): pass
          PYTHON
        blueprint_urls({{ framework }}, {"app.py" => source}).should eq(["/mounted/item"])
      end
    end

    it "resolves an imported alias in its declaring module" do
      blueprint_urls({{ framework }}, {
        "app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION
          from views import alias
          app = APPLICATION(__name__)
          app.register_blueprint(alias, url_prefix='/mounted')
          PYTHON
        "views.py" => <<-PYTHON,
          from FRAMEWORK import Blueprint
          bp = Blueprint('bp', __name__, url_prefix='/own')
          alias = bp
          @bp.get('/item')
          async def item(): pass
          PYTHON
      }).should eq(["/mounted/item"])
    end

    it "scopes app and blueprint names to each scan base" do
      blueprint_urls({{ framework }}, {
        "a/app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION
          shared = APPLICATION(__name__)
          PYTHON
        "b/app.py" => <<-PYTHON,
          from FRAMEWORK import APPLICATION, Blueprint
          from views import child
          app = APPLICATION(__name__)
          shared = Blueprint('shared', __name__, url_prefix='/parent')
          shared.register_blueprint(child)
          app.register_blueprint(shared, url_prefix='/mounted')
          PYTHON
        "b/views.py" => <<-PYTHON,
          from FRAMEWORK import Blueprint
          child = Blueprint('child', __name__, url_prefix='/child')
          @child.get('/item')
          async def item(): pass
          PYTHON
      }, true).should eq(["/mounted/child/item"])
    end
  end
{% end %}
