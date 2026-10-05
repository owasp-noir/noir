using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace Company.Function
{
    public class Products
    {
        [Function("GetProduct")]
        public HttpResponseData GetProduct(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "products/{id:int}")] HttpRequestData req,
            int id)
        {
            return req.CreateResponse(HttpStatusCode.OK);
        }

        [Function(nameof(SaveProduct))]
        public HttpResponseData SaveProduct(
            [HttpTrigger(AuthorizationLevel.Function, "post", "put", Route = "products")] HttpRequestData req)
        {
            return req.CreateResponse(HttpStatusCode.Created);
        }

        // Without methods the trigger answers every verb; without a route it
        // answers on the function name.
        [Function("Health")]
        public HttpResponseData Health([HttpTrigger(AuthorizationLevel.Anonymous)] HttpRequestData req)
        {
            return req.CreateResponse(HttpStatusCode.OK);
        }

        // [Function("Legacy")]
        // public HttpResponseData Legacy([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "legacy")] HttpRequestData req)

        [Function("Cleanup")]
        public void Cleanup([TimerTrigger("0 */5 * * * *")] TimerInfo timer)
        {
        }
    }
}
