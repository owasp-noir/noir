using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

[BindProperties]
public class OrdersModel : PageModel
{
    public string Note { get; set; }

    public int Total { get; private set; }

    public async Task<ActionResult<Dictionary<string, int>>> OnGetStatsAsync() => new();

    public IActionResult OnPostArchive([FromHeader(Name = "X-Token")] string token, [FromServices] AppDb db, [FromQuery] int limit) => Page();

    // public IActionResult OnDeleteLegacy(int id) => Page();
    /*
    public IActionResult OnPatch(int id) => Page();
    */
}
