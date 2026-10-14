public static class TodoEndpoints
{
    public static RouteGroupBuilder MapTodosApi(this RouteGroupBuilder group)
    {
        group.MapGet("/", GetAllTodos);
        group.MapGet("/{id}", GetTodo);
        group.MapPost("/", CreateTodo);
        return group;
    }

    public static async Task<Ok<Todo[]>> GetAllTodos(TodoDb database) => TypedResults.Ok(await database.Todos.ToArrayAsync());
    public static async Task<IResult> GetTodo(int id, TodoDb database) => TypedResults.Ok();
    public static async Task<IResult> CreateTodo(Todo todo, TodoDb database) => TypedResults.Ok();
}
