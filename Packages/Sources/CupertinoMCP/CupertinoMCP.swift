import ArgumentParser

// MARK: - Cupertino MCP Server CLI

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct CupertinoMCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cupertino-mcp",
        abstract: "MCP Server for Apple Documentation and Swift Evolution",
        version: "0.1.0",
        subcommands: [Serve.self],
        defaultSubcommand: Serve.self
    )
}
