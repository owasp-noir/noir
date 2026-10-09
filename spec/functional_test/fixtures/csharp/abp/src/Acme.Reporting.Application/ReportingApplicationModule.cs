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

    [HttpGet("api/reports/ping")] public Task<int> PingAsync() => Task.FromResult(1);

    [RemoteService(
        false)]
    public Task PurgeAsync() => Task.CompletedTask;

    // An enum binds from the query; a record DTO's fields go to the body.
    public Task ExportAsync(ReportFormat format, ExportRequest request) => Task.CompletedTask;

    public record ExportRequest(string Title, int Year);
}

public enum ReportFormat
{
    Pdf,
    Csv,
}
