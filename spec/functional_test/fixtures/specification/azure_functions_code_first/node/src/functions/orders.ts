import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";

export async function createOrder(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
    return { status: 201 };
}

app.http("createOrder", {
    methods: ["POST", "PUT"],
    authLevel: "function",
    route: "orders",
    handler: createOrder,
});

app.deleteRequest("deleteOrder", {
    route: "orders/{id}",
    handler: async () => ({ status: 204 }),
});
