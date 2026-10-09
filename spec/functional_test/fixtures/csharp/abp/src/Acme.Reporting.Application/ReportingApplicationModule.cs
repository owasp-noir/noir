using System.Threading.Tasks;
using Volo.Abp.Modularity;

namespace Acme.Reporting;

public class ReportingApplicationModule : AbpModule
{
}

public class SalesReportAppService : Volo.Abp.Application.Services.ApplicationService
{
    public Task<ReportDto> GetSummaryAsync(int year) => Task.FromResult(new ReportDto());

    public Task UpdateAsync(int id, string title) => Task.CompletedTask;

    public Task<Dictionary<string, int>> GetTotalsAsync() => Task.FromResult(new Dictionary<string, int>());
}
