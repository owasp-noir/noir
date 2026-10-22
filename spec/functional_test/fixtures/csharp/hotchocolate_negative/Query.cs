using Microsoft.AspNetCore.Mvc;

namespace Reports;

// A plain class named Query without HotChocolate: no GraphQL surface.
public class Query
{
    public string GetReport(int id) => "report";
}

public class QueryType
{
    public string Name { get; set; } = "";
}
