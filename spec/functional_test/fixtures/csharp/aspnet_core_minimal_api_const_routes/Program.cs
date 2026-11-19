var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

const string ApiPrefix = "/api/v1";
var version = "v2";

// Group templates held in a constant, a local and an interpolation.
var api = app.MapGroup(ApiPrefix);
api.MapGet("/c01", () => "x");

var api2 = app.MapGroup($"/api/{version}");
api2.MapGet("/c02", () => "x");

var nested = api.MapGroup("/c03");
nested.MapGet("/x", () => "x");

app.MapGroup(ApiRoutes.Admin).MapGet("/stats", () => "x");

// Route templates held in an interpolation and in `Type.Member` constants.
app.MapGet($"{ApiPrefix}/c05/{{id}}", (int id) => "x");
app.MapGet(ApiRoutes.Items.GetAll, () => "x");
app.MapPost(pattern: ApiRoutes.Items.Create, (NewItem item) => "x");

// Concatenations.
app.MapGet(ApiPrefix + "/c04", () => "x");
app.MapGet("/c08" + "/joined", () => "x");

app.MapGet("/c09/literal", () => "x");

app.Run();

record NewItem(string Name);

static class ApiRoutes
{
    public const string Admin = "/admin";

    public static class Items
    {
        public const string GetAll = "/c06/items";
        public const string Create = "/c07/items";
    }
}
