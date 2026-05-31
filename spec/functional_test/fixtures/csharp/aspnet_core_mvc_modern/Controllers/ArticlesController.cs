using System.Threading;
using System.Threading.Tasks;
using MediatR;
using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    // C# 12 primary constructor + attribute-routed controller deriving from the
    // framework Controller base. Actions are expression-bodied and delegate to
    // MediatR — the prevailing "thin controller" style.
    [Route("articles")]
    public class ArticlesController(IMediator mediator) : Controller
    {
        [HttpGet]
        public Task<ArticlesEnvelope> List(
            [FromQuery] string tag,
            [FromQuery] int? limit,
            CancellationToken cancellationToken
        ) => mediator.Send(new ListQuery(tag, limit), cancellationToken);

        [HttpGet("{slug}")]
        public Task<ArticleEnvelope> Get(string slug, CancellationToken cancellationToken) =>
            mediator.Send(new DetailsQuery(slug), cancellationToken);

        [HttpPost]
        public Task<ArticleEnvelope> Create(
            [FromBody] CreateArticleCommand command,
            CancellationToken cancellationToken
        ) => mediator.Send(command, cancellationToken);
    }
}
