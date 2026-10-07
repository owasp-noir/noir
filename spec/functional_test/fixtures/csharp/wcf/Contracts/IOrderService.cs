using System.IO;
using System.Threading.Tasks;
using System.ServiceModel;
using System.ServiceModel.Web;

namespace Shop.Contracts
{
    [ServiceContract]
    public interface IOrderService
    {
        [OperationContract]
        [WebGet(UriTemplate = "orders/{id}?expand={expand}", ResponseFormat = WebMessageFormat.Json)]
        Order GetOrder(string id, string expand);

        [OperationContract]
        [WebInvoke(Method = "POST", UriTemplate = "/orders", RequestFormat = WebMessageFormat.Json)]
        Order CreateOrder(Order order);

        [OperationContract, WebInvoke(Method = "PUT", UriTemplate = "orders/{id}")]
        void UpdateOrder(string id, Order order);

        [OperationContract]
        [WebInvoke(Method = WebRequestMethods.Http.Delete, UriTemplate = "orders/{id}")]
        void DeleteOrder(string id);

        // WebInvoke defaults to POST; no UriTemplate means the operation name.
        [OperationContract]
        [WebInvoke]
        void Ping(Stream payload);

        // WebGet without a template binds every parameter from the query.
        [OperationContract]
        [System.ServiceModel.Web.WebGet]
        Order[] Search(string q, int page);

        [OperationContract]
        [WebGet(UriTemplate = "files/{*path}")]
        Stream Download(string path);

        // The contract name, not the C# method name, is the default template.
        [OperationContract(Name = "Fetch")]
        [WebGet]
        Order Get(string id);

        // Task-based operations drop the `Async` suffix.
        [OperationContract]
        [WebGet]
        Task<Order> LatestAsync();

        [OperationContract]
        [WebGet(UriTemplate = "pages/{page=1}")]
        Order[] List(int page);

        [OperationContract]
        [WebInvoke(Method = "*", UriTemplate = "echo")]
        Stream Echo(Stream body);

        [OperationContract]
        [WebGet(UriTemplate = Routes.Hidden)]
        string Hidden();

        //[OperationContract]
        //[WebGet(UriTemplate = "commented-out")]
        //string Commented();
    }
}
