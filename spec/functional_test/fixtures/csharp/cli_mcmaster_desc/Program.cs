using System;
using McMaster.Extensions.CommandLineUtils;

class Program
{
    [Argument(0, Description = "the remote repository to push to")]
    public string Remote { get; set; }

    static int Main(string[] args) => CommandLineApplication.Execute<Program>(args);

    private void OnExecute() => Console.WriteLine(Remote);
}
