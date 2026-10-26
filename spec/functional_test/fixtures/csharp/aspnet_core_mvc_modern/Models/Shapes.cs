using System.Collections.Generic;
using System.Text.Json.Serialization;
using Newtonsoft.Json;

namespace Demo.Models.Shapes
{
    public class AccessorDto
    {
        private string _name;
        public string Name { get { return _name; } set { _name = value; } }
        public string Email
        {
            get { return _name; }
            set { _name = value; }
        }
        public string Computed { get { return _name + "x"; } }
        // Filled in place by Json.NET and form binding.
        public List<string> Tags { get; } = new List<string>();
    }

    public class SecretiveBase
    {
        public virtual string Secret { get; set; }
        public string Shadow { get; set; }
        public string Keep { get; set; }
    }

    // A redeclared member is the derived type's: its attributes win.
    public class OverridingDto : SecretiveBase
    {
        [System.Text.Json.Serialization.JsonIgnore] public override string Secret { get; set; }
        [JsonPropertyName("shadow_x")] public new string Shadow { get; set; }
    }

    // Json.NET binds a [JsonConstructor]'s parameters by name.
    public class CtorDto
    {
        [JsonConstructor]
        public CtorDto(string fooName, int count = default(int)) { Label = fooName; Count = count; }
        public string Label { get; }
        public int Count { get; }
    }

    public class Outer
    {
        public class Inner { public string Deep { get; set; } }
    }

    public class FromNested : Outer.Inner { public string Shallow { get; set; } }
}

namespace Demo.Models.Shapes.V1 { public class Versioned { public string FromV1 { get; set; } } }
namespace Demo.Models.Shapes.V2 { public class Versioned { public string FromV2 { get; set; } } }

namespace Demo.Models.Shapes { public class VersionedChild : V2.Versioned { public string Own { get; set; } } }
