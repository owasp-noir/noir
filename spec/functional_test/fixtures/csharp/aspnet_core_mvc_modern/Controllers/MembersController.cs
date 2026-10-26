using System.Collections.Generic;
using Demo.Models.Requests;
using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    // Body DTOs that inherit members, and a JSON array body.
    [Route("members")]
    public class MembersController : ControllerBase
    {
        // `MemberUpdateModel : MemberBase`: the base sits in the enclosing
        // namespace `Demo.Models`, which shadows the imported
        // `Demo.Shared.MemberBase`.
        [HttpPut("{id}")]
        public IActionResult Update(string id, [FromBody] MemberUpdateModel model) => Ok(model);

        // The base comes in through `using Demo.Shared;` and has a base of
        // its own.
        [HttpPost("trial")]
        public IActionResult Trial([FromBody] TrialModel model) => Ok(model);

        // The body is a JSON array of `EventDto`, so its members are the inputs.
        [HttpPost("events")]
        public IActionResult Events([FromBody] IEnumerable<EventDto> events) => Ok(events);

        [HttpPost("batch")]
        public IActionResult Batch([FromBody] EventDto[] events) => Ok(events);

        // `[BindNever]` and a binder that loads the value server-side take
        // nothing from the request; a binder reading `ModelName` does.
        [HttpGet("{id}/profile")]
        public IActionResult Profile(string id, [BindNever] EventDto current, [LoadMember] MemberUpdateModel loaded,
            [ModelBinder(typeof(CsvBinder))] int[] tags) => Ok(id);

        // Mutually derived types end the walk instead of looping.
        [HttpPost("cycle")]
        public IActionResult Cycle([FromBody] CycleA model) => Ok(model);
    }
}
