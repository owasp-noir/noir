using Carter;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using System.Threading.Tasks;

namespace CarterDemo.Modules
{
    // Derives from Carter's `CarterModule` base rather than implementing
    // `ICarterModule`, and hangs every route off the constructor base path.
    public class DirectorsModule : CarterModule
    {
        public DirectorsModule() : base("/directors")
        {
        }

        public override void AddRoutes(IEndpointRouteBuilder app)
        {
            app.MapGet("/", (ILogger<DirectorsModule> logger) => "directors");

            // A generic Map<Verb> registration.
            app.MapPut<Person>("/", (Person person) => "updated");

            app.MapGet("/qs", (string name, int[] numbers) => name);

            // app.MapDelete("/commented-out", () => "never registered");
        }
    }

    public class Person
    {
        public string Name { get; set; }
    }
}
