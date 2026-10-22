using Microsoft.AspNetCore.SignalR;

namespace SignalRDemo;

// A shared base hub (still a SignalR Hub underneath). AdminHub does not name
// `Hub` in its own base list — it is recognised as a hub only because
// `MapHub<AdminHub>` mounts it, which exercises the cross-file join.
public abstract class SecureHubBase : Hub
{
}

public class AdminHub : SecureHubBase
{
    public Task Kick(string userId)
    {
        return Clients.All.SendAsync("Kicked", userId);
    }
}
