using Microsoft.AspNetCore.Mvc;
using Web.Infrastructure;

namespace Web.Areas.Admin.Controllers;

[Area(AreaNames.ADMIN)]
public abstract class BaseAdminController : Controller
{
}

public class CategoryController : BaseAdminController
{
    public IActionResult List()
    {
        return View();
    }

    public IActionResult Edit(int id)
    {
        return View();
    }
}

// Same name as the public CustomerController: the pinned
// `customer/addressdelete` route must not reach this one.
public class CustomerController : BaseAdminController
{
    [HttpPost]
    public IActionResult AddressDelete(int customerId, int id)
    {
        return Json(new { Result = true });
    }
}
