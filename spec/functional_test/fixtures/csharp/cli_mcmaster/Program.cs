using System;
using McMaster.Extensions.CommandLineUtils;

[Subcommand(typeof(PushCommand))]
class Program
{
    [Option("-n|--name")]
    public string Name { get; set; }

    [Argument(0)]
    public string Input { get; set; }

    static int Main(string[] args)
    {
        var token = Environment.GetEnvironmentVariable("MCM_TOKEN");
        return CommandLineApplication.Execute<Program>(args);
    }

    private void OnExecute()
    {
        Console.WriteLine($"{Name}: {Input}");
    }
}

[Command("push")]
class PushCommand
{
    [Option("-f|--force")]
    public bool Force { get; set; }

    [Argument(0, "remote")]
    public string Remote { get; set; }

    private void OnExecute()
    {
        Console.WriteLine($"Pushing to {Remote}");
    }
}
