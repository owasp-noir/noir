require "../../../models/detector"

module Detector::CSharp
  # Detects C# command-line applications: programs using a CLI library
  # (System.CommandLine, CommandLineParser, CliFx, Spectre.Console.Cli) or a
  # `static Main(string[] args)` / GetCommandLineArgs entry point. Gates the C#
  # CLI analyzer. A web host (ASP.NET / HttpListener) suppresses the builtin
  # signals so a server's `Main`/env reads don't masquerade as a CLI.
  class Cli < Detector
    CLI_LIB   = /\busing\s+(?:System\.CommandLine|CommandLine|CliFx|Spectre\.Console\.Cli)\b/
    LIB_USAGE = /\bnew\s+RootCommand\s*\(|\bnew\s+CommandApp\b|\bCliApplicationBuilder\s*\(|\bParser\.Default\.ParseArguments\b|\[\s*Verb\s*\(|\[\s*CommandOption\s*\(|\[\s*CommandArgument\s*\(/
    WEB_HOST  = /\bWebApplication\.(?:Create(?:Builder|SlimBuilder|EmptyBuilder)?|CreateDefault)\b|\bnew\s+HttpListener\b|\.MapGet\s*\(|\.MapPost\s*\(|\.MapControllers\s*\(|\[\s*ApiController\s*\]|:\s*ControllerBase\b|\bHost\.CreateDefaultBuilder\b/
    MAIN_ARGS = /\bstatic\s+(?:async\s+)?(?:int|void|Task(?:<int>)?)\s+Main\s*\(\s*string\s*\[\s*\]\s+\w+\s*\)/
    GET_ARGS  = /\bEnvironment\.GetCommandLineArgs\s*\(/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cs")
      return true if file_contents.matches?(CLI_LIB) || file_contents.matches?(LIB_USAGE)
      return false if file_contents.matches?(WEB_HOST)
      file_contents.matches?(MAIN_ARGS) || file_contents.matches?(GET_ARGS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cs")
    end

    def set_name
      @name = "cs_cli"
    end
  end
end
