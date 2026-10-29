$version: "2"

namespace example.orders

resource Order {
    identifiers: { id: Uuid }
    properties: { coffeeType: String, note: String }
    read: GetOrder
    create: CreateOrder
}

@http(method: "POST", uri: "/order")
operation CreateOrder {
    input := for Order { @required $coffeeType $note }
}

@http(method: "GET", uri: "/order/{id}")
operation GetOrder {
    input := for Order { @httpLabel @required $id }
}

@http(method: "POST", uri: "/plain")
operation PlainOrder {
    input := { coffeeType: String, @httpQuery("verbose") verbose: Boolean }
}
