using System;
using Cocona;

var app = CoconaApp.Create();

// Several option/argument params on ONE inline-lambda line: every one
// must surface, not just the first (regression for line.scan fix).
app.AddCommand("run", ([Option('n')] string name, [Option('c')] int count, [Argument] string target) =>
{
    Console.WriteLine($"{name} {count} {target}");
});

app.Run();
