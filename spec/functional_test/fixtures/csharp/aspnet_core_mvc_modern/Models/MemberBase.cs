using System.Text.Json.Serialization;

namespace Demo.Models
{
    public abstract class MemberBase
    {
        public string ExternalId { get; set; }
        public required int? Role { get; set; }
        [JsonIgnore]
        public string Secret { get; set; }
        public AddressModel Home { get; set; }

        // A nested type's members belong to `home`, not to the body itself.
        public class AddressModel
        {
            public string Street { get; set; }
        }
    }
}
