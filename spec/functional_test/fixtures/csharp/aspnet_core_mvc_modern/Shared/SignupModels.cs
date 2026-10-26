namespace Demo.Shared;

public class SignupModel : ContactModel
{
    public string Name { get; set; }
}

public class ContactModel
{
    public string Email { get; set; }
}

// Same simple name as `Demo.Models.MemberBase` and imported by the member
// models' `using Demo.Shared;`, but their enclosing namespace's type wins.
public class MemberBase
{
    public string Decoy { get; set; }
}
