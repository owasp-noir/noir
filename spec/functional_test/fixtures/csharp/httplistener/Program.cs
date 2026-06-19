using System;
using System.IO;
using System.Net;
using System.Text;
using System.Threading.Tasks;

public static class Program
{
    public static async Task Main()
    {
        var listener = new HttpListener();
        listener.Prefixes.Add("http://localhost:8080/");
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
        var response = context.Response;
        var method = request.HttpMethod;
        var path = request.Url?.AbsolutePath ?? "/";

        if (method == "GET" && path == "/health")
        {
            var trace = request.Headers["X-Trace-Id"];
            Write(response, $"ok {trace}");
        }
        else if (path == "/search" && method.Equals("GET", StringComparison.OrdinalIgnoreCase))
        {
            var query = request.QueryString;
            var q = query["q"];
            var page = query.Get("page");
            Write(response, $"{q}:{page}");
        }
        else if (method == "POST" && path == "/users")
        {
            var contentType = request.Headers.Get("Content-Type");
            using var reader = new StreamReader(request.InputStream, request.ContentEncoding);
            var body = await reader.ReadToEndAsync();
            Write(response, $"{contentType}:{body}");
        }
        else if ("DELETE".Equals(method, StringComparison.OrdinalIgnoreCase) && path == "/users/delete")
        {
            var sid = request.Cookies["sid"]?.Value;
            Write(response, sid ?? "");
        }
        else if (path == "/ready")
        {
            Write(response, "ready");
        }

        switch (path)
        {
            case "/status":
                if (method == "HEAD")
                {
                    response.StatusCode = 204;
                }
                break;
        }

        switch (method)
        {
            case "PUT":
                if (path == "/users")
                {
                    var requestId = request.Headers["X-Request-Id"];
                    Write(response, requestId ?? "");
                }
                break;
        }

        switch ((method, path))
        {
            case ("PATCH", "/users/profile"):
                var include = request.QueryString["include"];
                Write(response, include ?? "");
                break;
        }
    }

    private static void Write(HttpListenerResponse response, string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        response.OutputStream.Write(bytes, 0, bytes.Length);
    }
}
