var builder = WebApplication.CreateBuilder(args);
builder.Services.AddMvc(opt => opt.Conventions.Add(new ApiRoutePrefixConvention("api")));
var app = builder.Build();
app.MapControllers();
if (app.Environment.IsDevelopment())
{
    app.MapHealthChecks("/health");
}
app.MapForwarder("/product-images/{id}", "https+http://catalog-api", "/api/catalog/items/{id}/pic");
app.Run();
