using System;
using Volo.Abp.Application.Dtos;
using Volo.Abp.Application.Services;

namespace Acme.BookStore;

public class GetBookListDto : PagedAndSortedResultRequestDto
{
    public string? Filter { get; set; }
}

public class CreateBookDto
{
    public string Name { get; set; }
    public float Price { get; set; }
}

public class CreateUpdateAuthorDto
{
    public string Name { get; set; }
    public DateTime BirthDate { get; set; }
}

public interface IBookAppService : IApplicationService
{
}
