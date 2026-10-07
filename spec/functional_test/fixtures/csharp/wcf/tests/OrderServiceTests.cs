using System.ServiceModel;
using System.ServiceModel.Web;

[ServiceContract]
public interface ITestOnly
{
    [OperationContract]
    [WebGet(UriTemplate = "test-only")]
    string TestOnly();
}
