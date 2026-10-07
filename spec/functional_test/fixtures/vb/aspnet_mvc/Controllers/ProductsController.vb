Imports Microsoft.AspNetCore.Mvc

<ApiController>
<Route("api/[controller]")>
Public Class ProductsController
    Inherits ControllerBase

    <HttpGet>
    Public Async Function List(<FromQuery> category As String) As Task(Of IActionResult)
        Return Ok()
    End Function

    <HttpGet("{id:int}")>
    Public Function GetById(id As Integer) As ActionResult(Of Product)
        Return Ok()
    End Function

    <HttpPost> _
    Public Function Create(<FromBody> product As Product, <FromHeader(Name:="X-Api-Key")> apiKey As String) As IActionResult
        Return Ok()
    End Function

    <HttpDelete("{id}")>
    Public Function Remove(id As Integer, <FromServices> repo As IProductRepository) As IActionResult
        Return Ok()
    End Function

    <HttpGet("[action]")>
    Public Function Export() As IActionResult
        Return Ok()
    End Function
End Class
