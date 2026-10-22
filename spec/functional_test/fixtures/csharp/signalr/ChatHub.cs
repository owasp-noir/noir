using Microsoft.AspNetCore.SignalR;

namespace SignalRDemo;

public class ChatHub : Hub
{
    private readonly ILogger<ChatHub> _logger;

    public ChatHub(ILogger<ChatHub> logger) => _logger = logger;

    // Client-callable event with two message params.
    public async Task SendMessage(string user, string message)
    {
        await Clients.All.SendAsync("ReceiveMessage", user, message);
    }

    // Client-callable event with a single param.
    public Task JoinRoom(string roomName)
    {
        return Groups.AddToGroupAsync(Context.ConnectionId, roomName);
    }

    // A trailing CancellationToken is a framework/DI type, not a message
    // field, so it must be dropped from the params.
    public async Task StreamData(int count, CancellationToken cancellationToken)
    {
        await Task.Delay(count, cancellationToken);
    }

    // Lifecycle override — never a client-invocable event.
    public override async Task OnConnectedAsync()
    {
        await base.OnConnectedAsync();
    }
}
