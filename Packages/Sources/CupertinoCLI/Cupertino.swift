import ArgumentParser

// MARK: - Cupertino CLI

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct Cupertino: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cupertino",
        abstract: "Apple Documentation Crawler and Indexer",
        version: "0.1.0",
        subcommands: [Crawl.self, Fetch.self, Index.self],
        defaultSubcommand: Crawl.self
    )
}
