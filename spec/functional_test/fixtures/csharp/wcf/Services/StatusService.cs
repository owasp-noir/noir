using CoreWCF;
using CoreWCF.Web;

namespace Shop.Services
{
    // CoreWCF: the attributes sit on the service class itself.
    [ServiceContract]
    public class StatusService
    {
        [OperationContract]
        [WebGet(UriTemplate = "status")]
        public string Status() => "ok";

        [OperationContract]
        [WebInvoke(Method = "PATCH", UriTemplate = "status/{component}")]
        public void SetStatus(string component, [MessageParameter(Name = "s")] string state)
        {
        }
    }
}
