using System;
using System.Threading.Tasks;
using Volo.Abp;
using Volo.Abp.Application.Dtos;
using Volo.Abp.Application.Services;
using Volo.Abp.Domain.Repositories;

namespace Acme.BookStore.Authors;

public class AuthorAppService :
    CrudAppService<Author, AuthorDto, Guid, PagedAndSortedResultRequestDto, CreateUpdateAuthorDto>,
    IAuthorAppService
{
    public AuthorAppService(IRepository<Author, Guid> repository) : base(repository)
    {
    }

    // Overrides the inherited action; the conventional endpoint is reported once.
    public override async Task<AuthorDto> GetAsync(Guid id)
    {
        return await base.GetAsync(id);
    }

    // Hides the inherited DELETE.
    [RemoteService(false)]
    public override Task DeleteAsync(Guid id)
    {
        return base.DeleteAsync(id);
    }
}

// Not exposed: the whole service opts out of remoting.
[RemoteService(IsEnabled = false)]
public class AuthorSyncAppService : ApplicationService
{
    public Task SyncAsync() => Task.CompletedTask;
}
