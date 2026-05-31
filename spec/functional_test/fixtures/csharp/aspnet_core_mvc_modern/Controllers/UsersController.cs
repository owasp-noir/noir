using System.Threading;
using System.Threading.Tasks;
using MediatR;
using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    // POCO controller: no `: Controller` / `: ControllerBase` base class. ASP.NET
    // Core still treats it as a controller by the `Controller` name suffix.
    [Route("users")]
    public class UsersController(IMediator mediator)
    {
        [HttpPost]
        public Task<UserEnvelope> Create(
            [FromBody] RegisterCommand command,
            CancellationToken cancellationToken
        ) => mediator.Send(command, cancellationToken);

        [HttpPost("login")]
        public Task<UserEnvelope> Login(
            [FromBody] LoginCommand command,
            CancellationToken cancellationToken
        ) => mediator.Send(command, cancellationToken);
    }
}
