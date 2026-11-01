require "../../spec_helper"
require "../../../src/miniparsers/ts_decorator_extractor"

describe Noir::TsDecoratorExtractor do
  it "reads a .js controller whose handler returns JSX, and the routes after it" do
    source = <<-JS
      @Controller('pages')
      export class PagesController {
        @Get('home')
        home() { return <div>hi</div>; }

        @Get('about')
        about(@Query('lang') lang) { return lang; }
      }
      JS
    klass = Noir::TsDecoratorExtractor.extract(source, "pages.controller.js").first
    klass.methods.map(&.name).should eq(["home", "about"])
    klass.methods.last.params.first.decorators.first.args.should eq(["'lang'"])
  end

  it "keeps TypeScript `<T>x` casts in .ts files" do
    source = <<-TS
      @Controller('c')
      export class C {
        @Get('a')
        a() { return <string>value; }

        @Get('b')
        b() { return 1; }
      }
      TS
    Noir::TsDecoratorExtractor.extract(source, "c.controller.ts").first.methods.map(&.name).should eq(["a", "b"])
  end
end
