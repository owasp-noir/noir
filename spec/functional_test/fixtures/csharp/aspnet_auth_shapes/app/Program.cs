var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();
app.MapControllers();
app.MapGroup("/organizations/{orgId:guid}/access-rules").MapAccessRuleEndpoints();
app.MapGroup("/public").MapPublicEndpoints();
app.Run();
