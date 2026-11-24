using Microsoft.AspNetCore.Authorization;

namespace BlazorAuth.Components.Pages;

[Authorize(Policy = "Buyers")]
public partial class Orders
{
}
