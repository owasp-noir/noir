using Microsoft.AspNetCore.SignalR;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSignalR();
var app = builder.Build();

// Hub mounts. Routes and hub classes live in separate files on purpose.
app.MapHub<ChatHub>(/* realtime */ "/chat");
app.MapHub<NotificationHub>("/notify");
app.MapHub<AdminHub>("/admin");

app.Run();
