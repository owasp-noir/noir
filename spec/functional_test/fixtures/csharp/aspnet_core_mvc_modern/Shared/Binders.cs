using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace Demo.Shared;

public sealed class LoadMemberAttribute() : ModelBinderAttribute(typeof(MemberLoader));

// Loads the entity by the route id: no request value is bound.
public class MemberLoader : IModelBinder
{
    public Task BindModelAsync(ModelBindingContext bindingContext)
    {
        var id = bindingContext.HttpContext.GetRouteValue("id");
        bindingContext.Result = ModelBindingResult.Success(id);
        return Task.CompletedTask;
    }
}

// Reads the value posted under the parameter's own name.
public class CsvBinder : IModelBinder
{
    public Task BindModelAsync(ModelBindingContext bindingContext)
    {
        var raw = bindingContext.ValueProvider.GetValue(bindingContext.ModelName);
        bindingContext.Result = ModelBindingResult.Success(raw.FirstValue);
        return Task.CompletedTask;
    }
}

// Reads the raw request: the parameter stays.
public class QueryBinder : IModelBinder
{
    public Task BindModelAsync(ModelBindingContext bindingContext)
    {
        var raw = bindingContext.HttpContext.Request.Query["filter"];
        bindingContext.Result = ModelBindingResult.Success(raw.ToString());
        return Task.CompletedTask;
    }
}

// Reads one fixed key: that key is what the client sends.
public class FixedKeyBinder : IModelBinder
{
    public Task BindModelAsync(ModelBindingContext bindingContext)
    {
        var raw = bindingContext.ValueProvider.GetValue("sort");
        bindingContext.Result = ModelBindingResult.Success(raw.FirstValue);
        return Task.CompletedTask;
    }
}

// Inherits the `ModelName` read from its base.
public class DerivedCsvBinder : CsvBinder
{
}
