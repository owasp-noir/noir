using System;
using System.Threading.Tasks;
using Volo.Abp.Application.Services;
using Volo.Abp.Modularity;

namespace Acme.Identity;

// No `ConventionalControllers.Create` covers this assembly: a module that
// exposes its services through hand-written controllers instead.
public class IdentityApplicationModule : AbpModule
{
}

public class IdentityUserAppService : ApplicationService
{
    public Task<IdentityUserDto> GetAsync(Guid id) => Task.FromResult(new IdentityUserDto());
}
