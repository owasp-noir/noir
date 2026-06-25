using System;
using System.CommandLine;

class Program
{
    static int Main(string[] args)
    {
        var root = new RootCommand("My tool");
        root.AddOption(new Option<bool>("--verbose"));

        var serve = new Command("serve", "Start the server");
        serve.AddOption(new Option<int>("--port"));
        serve.AddArgument(new Argument<string>("config"));
        root.AddCommand(serve);

        var token = Environment.GetEnvironmentVariable("API_TOKEN");
        return root.Invoke(args);
    }
}
