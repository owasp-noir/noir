Imports System.Threading
Imports System.Web.Http

Namespace Controllers
    <RoutePrefix("api/users")>
    Public Class UsersController
        Inherits ApiController

        <HttpGet>
        <Route("")>
        Public Function GetAll(Optional ByVal page As Integer = 1) As IHttpActionResult
            Return Ok()
        End Function

        <HttpGet, Route("{id:int}")>
        Public Function GetUser(ByVal id As Integer) As IHttpActionResult
            Return Ok()
        End Function

        <Route("")>
        <HttpPost>
        Public Function CreateUser(<FromBody> ByVal user As UserDto) As IHttpActionResult
            Return Ok()
        End Function

        <HttpPut>
        <Route("{id}")>
        Public Function UpdateUser(id As Integer,
                                   <FromBody> user As UserDto) As IHttpActionResult
            Return Ok()
        End Function

        ' No verb attribute: Web API takes the verb from the name prefix.
        <Route("{id}")>
        Public Function DeleteUser(id As Integer) As IHttpActionResult
            Return Ok()
        End Function

        <Route("~/api/health")> <HttpGet>
        Public Function Health() As IHttpActionResult
            Return Ok()
        End Function

        <HttpGet>
        <Route("search")>
        Public Async Function Search(<FromUri> ByVal q As String, ByVal cancellationToken As CancellationToken) As Task(Of IHttpActionResult)
            Return Ok()
        End Function

        ' No <Route>: <RoutePrefix> does not apply, MapHttpRoute does.
        Public Function GetCount() As Integer
            Return 0
        End Function

        Private Function Helper() As String
            Return "<HttpGet>"
        End Function
    End Class
End Namespace
