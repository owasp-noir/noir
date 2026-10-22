using Volo.Abp.AspNetCore.Mvc;
using Volo.Abp.Modularity;
using Acme.BookStore;
using Acme.Reporting;

namespace Acme.BookStore.Host;

[DependsOn(typeof(AbpAspNetCoreMvcModule))]
public class BookStoreHttpApiHostModule : AbpModule
{
    public override void ConfigureServices(ServiceConfigurationContext context)
    {
        Configure<AbpAspNetCoreMvcOptions>(options =>
        {
            options.ConventionalControllers.Create(typeof(BookStoreApplicationModule).Assembly);
            options.ConventionalControllers.Create(typeof(ReportingApplicationModule).Assembly, opts =>
            {
                opts.RootPath = "reporting";
            });
        });
    }
}
