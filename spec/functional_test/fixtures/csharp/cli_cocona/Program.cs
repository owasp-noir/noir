using System;
using Cocona;

var app = CoconaApp.Create();

app.AddCommand("greet", ([Option('n')] string name, [Argument] string message) =>
{
    var token = Environment.GetEnvironmentVariable("COCONA_TOKEN");
    Console.WriteLine($"Hello {name}: {message}");
});

app.AddCommand("bye", () => Console.WriteLine("bye"));

app.Run();
