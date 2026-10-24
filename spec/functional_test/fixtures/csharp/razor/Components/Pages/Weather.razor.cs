public partial class Weather
{
    [SupplyParameterFromQuery]
    public string? City { get; set; }

    protected override async Task OnInitializedAsync()
    {
    }
}
