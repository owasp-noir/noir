using Microsoft.AspNetCore.Mvc;
using Volo.Abp.AspNetCore.Mvc;

namespace Acme.BookStore.Host.Controllers;

[Route("api/ping")]
public class PingController : AbpController
{
    [HttpGet]
    public string Get() => "pong";
}
