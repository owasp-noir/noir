var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorPages(options =>
{
    options.Conventions.AuthorizePage("/Basket/Checkout");
    options.Conventions.AuthorizeFolder("/Reports", "ReportReaders")
        .AllowAnonymousToPage("/Reports/Public");
    options.Conventions.AuthorizeAreaFolder("Identity", "/Manage");
});
var app = builder.Build();
app.MapRazorPages();
app.Run();
