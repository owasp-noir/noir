using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;

namespace Demo.Endpoints
{
    public class OrderEndpoint
    {
        public void Register(Microsoft.AspNetCore.Routing.IEndpointRouteBuilder routeBuilder)
        {
            routeBuilder.MapPost("/mapped/orders/{id}", async context =>
            {
                var query = context.Request.Query["expand"];
                var saved = await orderService.Save(context);
                AuditLog.Write("minimal");
                await context.Response.WriteAsync(SerializeOrder(saved));
            });
        }
    }
}
