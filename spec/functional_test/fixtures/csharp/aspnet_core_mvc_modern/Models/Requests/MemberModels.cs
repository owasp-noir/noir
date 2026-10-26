using System.Text.Json.Serialization;
using Demo.Shared;

namespace Demo.Models.Requests;

public class MemberUpdateModel : MemberBase
{
    public string Email { get; set; }
    // camelCased as the JSON naming policy does: `otp`.
    public string OTP { get; set; }
    public string[] Tags { get; set; }

    // Never written from the request: computed, getter-only, privately set.
    public bool IsValid { get { return Email != null; } }
    public string Display { get; }
    public int Revision { get; private set; }
}

public class TrialModel : SignupModel
{
    public int TrialLength { get; init; }
}

public class EventDto
{
    public int Type { get; set; }
    [JsonPropertyName("ts")]
    public long Date { get; set; }
}

public class CycleA : CycleB
{
    public string Left { get; set; }
}

public class CycleB : CycleA
{
    public string Right { get; set; }
}
