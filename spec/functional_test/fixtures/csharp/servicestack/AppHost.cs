using ServiceStack;
using ServiceStackDemo.ServiceModel;

namespace ServiceStackDemo
{
    public class AppHost : AppHostBase
    {
        public AppHost() : base("ServiceStack Demo", typeof(AppHost).Assembly) { }

        public override void Configure(Container container)
        {
            // Chained fluent registration: both calls resolve to Hello's
            // Name property, declared in a different file.
            Routes
                .Add<Hello>("/hello2")
                .Add<Hello>("/hello2/{Name}");

            // Single-statement fluent registration with an explicit verb.
            Routes.Add<GetContact>("/contacts", "GET");
        }
    }
}
