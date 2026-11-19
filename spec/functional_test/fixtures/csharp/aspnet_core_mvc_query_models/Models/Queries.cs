using Microsoft.AspNetCore.Mvc;

namespace App.Models;

public class PagingQuery
{
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 20;
}

public class ProductQuery : PagingQuery
{
    public string? Term { get; set; }

    [FromQuery(Name = "sort_by")]
    public string? SortBy { get; set; }

    public decimal? MinPrice { get; set; }
}

public class CreateProduct
{
    public string Name { get; set; } = "";
    public decimal Price { get; set; }
}
