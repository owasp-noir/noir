using System.Text.Json.Serialization;

public class WebhookRequest
{
    public string Url { get; set; }

    [JsonPropertyName("grant_url")]
    public string GrantUrl { get; set; }

    [JsonIgnore]
    public string Secret { get; set; }
}
