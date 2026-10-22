namespace BookStore;

// HC 14+ source generator: a single [Query] member joins the Query root.
public static class HealthFields
{
    [Query]
    public static string GetHealth() => "ok";

    // Not marked: a plain static helper, never a field.
    public static string Helper() => "helper";
}
