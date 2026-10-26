using Demo.Models.Shapes;
using Demo.Shared;
using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    // Property and type shapes a body DTO's members come from.
    [Route("shapes")]
    public class ShapesController : ControllerBase
    {
        [HttpPost("accessors")]
        public IActionResult Accessors([FromBody] AccessorDto dto) => Ok(dto);

        [HttpPost("override")]
        public IActionResult Override([FromBody] OverridingDto dto) => Ok(dto);

        [HttpPost("ctor")]
        public IActionResult Ctor([FromBody] CtorDto dto) => Ok(dto);

        // `V2.Versioned`, not the `V1` one declared first in the same file.
        [HttpPost("versioned")]
        public IActionResult Versioned([FromBody] VersionedChild dto) => Ok(dto);

        [HttpPost("nested-base")]
        public IActionResult NestedBase([FromBody] FromNested dto) => Ok(dto);

        [HttpPost("grid")]
        public IActionResult Grid([FromBody] int[,] grid) => Ok(grid);

        // Binders that read the request keep the parameter; a fixed
        // value-provider key renames it.
        [HttpGet("binders")]
        public IActionResult Binders([ModelBinder(typeof(QueryBinder))] string filter,
            [ModelBinder(BinderType = typeof(FixedKeyBinder))] string order,
            [ModelBinder(typeof(DerivedCsvBinder))] int[] ids) => Ok(filter);
    }
}
