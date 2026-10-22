using System;
using System.Net;
using System.Threading.Tasks;

public static class ProgramB
{
    public static async Task Main()
    {
        var listener = new HttpListener();
        listener.Prefixes.Add("http://localhost:9090/");
        listener.Start();
        while (true)
        {
            var context = await listener.GetContextAsync();
            await Handle(context);
        }
    }

    private static async Task Handle(HttpListenerContext context)
    {
        var request = context.Request;
        var method = request.HttpMethod;
        var path = request.Url?.AbsolutePath ?? "/";

        if (method == "GET" && path == "/health")
        {
            var beta = request.Headers["X-Beta"];
            Console.WriteLine(beta);
        }
    }
}
