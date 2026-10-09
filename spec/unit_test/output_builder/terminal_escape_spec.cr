require "../../spec_helper"
require "../../../src/output_builder/*"
require "../../../src/models/endpoint"
require "../../../src/models/passive_scan"
require "../../../src/utils/utils"

private def terminal_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
    "output"  => YAML::Any.new(""),
  }
end

private def render(builder, endpoints : Array(Endpoint)) : String
  builder.io = IO::Memory.new
  builder.print(endpoints, [] of PassiveScanResult)
  builder.io.to_s
end

private def hostile_endpoint : Endpoint
  endpoint = Endpoint.new("/x\e]8;;http://evil.example\aclick", "GET")
  endpoint.push_param(Param.new("q\e[2J", "", "query"))
  endpoint.push_param(Param.new("h\e[31mdr", "\u009b1m", "header"))
  endpoint.push_param(Param.new("c\e[1mk", "", "cookie"))
  endpoint.push_param(Param.new("f\e[1m", "", "form"))
  endpoint
end

# Raw control characters other than the line breaks the report itself writes.
private def raw_controls(output : String) : Array(Char)
  output.chars.select { |char| ControlChars.control?(char) && char != '\n' }
end

# Every format below prints repo-derived text straight to the terminal. Only
# the plain report escaped it, so `-f only-url`, `-f curl` and the rest
# replayed a route's `\e]8;;…\a` hyperlink or `\e[2J` screen clear verbatim.
describe "terminal escapes in stdout formats" do
  # A macro, not a loop over classes: called through the `OutputBuilder`
  # base type, the one-argument `print` resolves to `Kernel#print`.
  {% for pair in [{"only-url", OutputBuilderOnlyUrl}, {"only-param", OutputBuilderOnlyParam},
                  {"only-header", OutputBuilderOnlyHeader}, {"only-cookie", OutputBuilderOnlyCookie},
                  {"curl", OutputBuilderCurl}, {"httpie", OutputBuilderHttpie},
                  {"powershell", OutputBuilderPowershell}, {"markdown-table", OutputBuilderMarkdownTable}] %}
    it "escapes them in -f {{ pair[0].id }}" do
      output = render({{ pair[1] }}.new(terminal_options), [hostile_endpoint])
      raw_controls(output).should be_empty
      output.should_not be_empty
    end
  {% end %}

  it "shows them as \\xNN in the shell-quoted commands" do
    render(OutputBuilderCurl.new(terminal_options), [hostile_endpoint]).should contain("'/x\\x1b]8;;http://evil.example\\x07click?q\\x1b[2J='")
  end

  it "keeps the PowerShell string faithful with a [char] subexpression" do
    render(OutputBuilderPowershell.new(terminal_options), [hostile_endpoint]).should contain(%("h$([char]0x1B)[31mdr"="$([char]0x9B)1m"))
  end

  it "escapes them in adb and simctl launch commands" do
    android = Endpoint.new("myapp://h/\e[2J", "GET")
    android.protocol = "mobile-scheme"
    ios = Endpoint.new("myapp://h/\e[2J", "GET")
    ios.protocol = "mobile-scheme"
    ios.details.technology = "ios"

    adb = render(OutputBuilderAdb.new(terminal_options), [android])
    simctl = render(OutputBuilderSimctl.new(terminal_options), [ios])

    raw_controls(adb).should be_empty
    raw_controls(simctl).should be_empty
    simctl.should contain("'myapp://h/\\x1b[2J'")
  end

  it "escapes passive-scan extracts and file paths" do
    rule = PassiveScan.new(YAML.parse(<<-YAML))
      id: test-rule
      info:
        name: "Test Rule"
        author: ["t"]
        severity: "high"
        description: "d"
        reference: []
      matchers-condition: "or"
      matchers:
        - type: "regex"
          patterns: ["x"]
          condition: "or"
      category: "secret"
      techs: ["*"]
      YAML
    builder = OutputBuilderPassiveScan.new(terminal_options)
    builder.io = IO::Memory.new
    builder.print([PassiveScanResult.new(rule, "se\e[31mcrets.js", 1, "KEY = \"x\e[2Jy\a\"")])
    output = builder.io.to_s

    raw_controls(output).should be_empty
    output.should contain("extract: KEY = \"x\\x1b[2Jy\\x07\"")
    output.should contain("file: se\\x1b[31mcrets.js:1")
  end
end
