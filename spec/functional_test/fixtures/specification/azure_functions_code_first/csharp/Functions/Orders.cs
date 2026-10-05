using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;

public static class Orders
{
    // In-process model: `FunctionName` + `Route = null` falls back to the name.
    [FunctionName("ListOrders")]
    public static IActionResult Run(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = null)] HttpRequest req)
    {
        return new OkResult();
    }

    [FunctionName("PatchOrder")]
    public static IActionResult Patch(
        [HttpTrigger(AuthLevel = AuthorizationLevel.Admin, Methods = new[] { "patch" }, Route = "orders/{id}")] HttpRequest req,
        string id)
    {
        return new OkResult();
    }
}
