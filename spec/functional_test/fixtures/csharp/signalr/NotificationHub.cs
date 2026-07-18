using Microsoft.AspNetCore.SignalR;

namespace SignalRDemo;

// A hub with no client-callable methods (only a lifecycle override). It
// still exposes a connection surface, so a bare `ws://notify` endpoint is
// emitted.
public class NotificationHub : Hub
{
    public override Task OnConnectedAsync() => base.OnConnectedAsync();
}
