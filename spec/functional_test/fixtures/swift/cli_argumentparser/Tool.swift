import ArgumentParser

struct Tool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tool",
        subcommands: [Serve.self]
    )

    @Flag(name: .shortAndLong) var verbose = false
}

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "serve")

    @Option(name: .long) var port: Int = 8080
    @Argument var config: String
}
