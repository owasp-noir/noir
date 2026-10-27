using Microsoft.AspNetCore.Mvc;

namespace Web.Controllers;

public class CustomerController : Controller
{
    public IActionResult Login()
    {
        return View();
    }

    [HttpPost]
    public IActionResult Login(string email, string password)
    {
        return RedirectToAction("Index", "Home");
    }

    [HttpPost]
    public IActionResult AddressDelete(int addressId)
    {
        return Json(new { redirect = "/customer/addresses" });
    }
}

public class OrderController : Controller
{
    public IActionResult GetPdfInvoice(int orderId)
    {
        return File(new byte[0], "application/pdf");
    }
}

public class ProductController : Controller
{
    public IActionResult ProductDetails(int productId, int updatecartitemid = 0)
    {
        return View();
    }
}
