import ArgumentParser
import CupertinoCore
import CupertinoLogging
import CupertinoSearch
import CupertinoShared
import Foundation

// MARK: - Crawl Command

extension Cupertino {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Crawl: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Crawl documentation using WKWebView"
        )

        @Option(name: .long, help: "Type of documentation to crawl: docs (Apple), swift (Swift.org), evolution (Swift Evolution), packages (Swift packages)")
        var type: CrawlType = .docs

        @Option(name: .long, help: "Start URL to crawl from (overrides --type default)")
        var startURL: String?

        @Option(name: .long, help: "Maximum number of pages to crawl")
        var maxPages: Int = 15000

        @Option(name: .long, help: "Maximum depth to crawl")
        var maxDepth: Int = 15

        @Option(name: .long, help: "Output directory for documentation")
        var outputDir: String?

        @Option(name: .long, help: "Allowed URL prefixes (comma-separated). If not specified, auto-detects based on start URL")
        var allowedPrefixes: String?

        @Flag(name: .long, help: "Force recrawl of all pages")
        var force: Bool = false

        @Flag(name: .long, help: "Resume from saved session (auto-detects and continues)")
        var resume: Bool = false

        @Flag(name: .long, help: "Only download accepted/implemented proposals (evolution type only)")
        var onlyAccepted: Bool = false

        mutating func run() async throws {
            if resume {
                ConsoleLogger.info("🔄 AppleCupertino - Resuming from saved session\n")
            } else {
                ConsoleLogger.info("🚀 AppleCupertino - Crawling \(type.displayName)\n")
            }

            // Handle "all" type - crawl everything in parallel
            if type == .all {
                ConsoleLogger.info("📚 Crawling all documentation types in parallel:\n")

                // Capture values before entering task group
                let baseCommand = self

                try await withThrowingTaskGroup(of: (CrawlType, Result<Void, Error>).self) { group in
                    // Launch all crawls concurrently
                    for crawlType in CrawlType.allTypes {
                        group.addTask {
                            ConsoleLogger.info("🚀 Starting \(crawlType.displayName)...")
                            var crawlCommand = baseCommand
                            crawlCommand.type = crawlType
                            crawlCommand.outputDir = crawlType.defaultOutputDir

                            do {
                                try await crawlCommand.run()
                                return (crawlType, .success(()))
                            } catch {
                                return (crawlType, .failure(error))
                            }
                        }
                    }

                    // Collect results
                    var results: [(CrawlType, Result<Void, Error>)] = []
                    for try await result in group {
                        results.append(result)
                        let (crawlType, outcome) = result
                        switch outcome {
                        case .success:
                            ConsoleLogger.info("✅ Completed \(crawlType.displayName)")
                        case .failure(let error):
                            ConsoleLogger.error("❌ Failed \(crawlType.displayName): \(error)")
                        }
                    }

                    // Check if any failed
                    let failures = results.filter {
                        if case .failure = $0.1 { return true }
                        return false
                    }

                    if failures.isEmpty {
                        ConsoleLogger.info("\n✅ All documentation types crawled successfully!")
                    } else {
                        ConsoleLogger.info("\n⚠️  Completed with \(failures.count) failure(s)")
                        throw ExitCode.failure
                    }
                }
                return
            }

            // Handle evolution type specially (uses different crawler)
            if type == .evolution {
                try await runEvolutionCrawl()
                return
            }

            // Determine start URL
            let urlString = startURL ?? type.defaultURL
            guard let url = URL(string: urlString) else {
                throw ValidationError("Invalid start URL: \(urlString)")
            }

            // Auto-detect output directory based on type if not provided
            let defaultOutputDir: String
            if let outputDir {
                defaultOutputDir = outputDir
            } else {
                // Check for existing session to resume from
                let homeDir = FileManager.default.homeDirectoryForCurrentUser
                let defaultCandidates = [
                    homeDir.appendingPathComponent(".cupertino/docs"),
                    homeDir.appendingPathComponent(".cupertino/swift-org"),
                    homeDir.appendingPathComponent(".cupertino/swift-book"),
                ]

                var foundSession: String?

                // Helper function to check a metadata file
                func checkMetadataFile(_ metadataFile: URL) -> String? {
                    guard FileManager.default.fileExists(atPath: metadataFile.path) else { return nil }
                    guard let data = try? Data(contentsOf: metadataFile),
                          let metadata = try? JSONDecoder().decode(CrawlMetadata.self, from: data),
                          let session = metadata.crawlState,
                          session.isActive,
                          session.startURL == url.absoluteString else { return nil }
                    return session.outputDirectory
                }

                // Check default candidates first
                for candidate in defaultCandidates {
                    let metadataFile = candidate.appendingPathComponent("metadata.json")
                    if let outputDir = checkMetadataFile(metadataFile) {
                        foundSession = outputDir
                        ConsoleLogger.info("📂 Found existing session, resuming to: \(outputDir)")
                        break
                    }
                }

                // If not found in defaults, check other common locations
                if foundSession == nil {
                    let cupertinoDir = homeDir.appendingPathComponent(".cupertino")
                    if let contents = try? FileManager.default.contentsOfDirectory(
                        at: cupertinoDir,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        for dir in contents where (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                            let metadataFile = dir.appendingPathComponent("metadata.json")
                            if let outputDir = checkMetadataFile(metadataFile) {
                                foundSession = outputDir
                                ConsoleLogger.info("📂 Found existing session, resuming to: \(outputDir)")
                                break
                            }
                        }
                    }
                }

                defaultOutputDir = foundSession ?? type.defaultOutputDir
            }

            let outputDirectory = URL(fileURLWithPath: defaultOutputDir).expandingTildeInPath

            // Parse allowed prefixes if provided
            let prefixes: [String]? = allowedPrefixes?.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }

            let config = CupertinoConfiguration(
                crawler: CrawlerConfiguration(
                    startURL: url,
                    allowedPrefixes: prefixes,
                    maxPages: maxPages,
                    maxDepth: maxDepth,
                    outputDirectory: outputDirectory
                ),
                changeDetection: ChangeDetectionConfiguration(
                    forceRecrawl: force,
                    outputDirectory: outputDirectory
                ),
                output: OutputConfiguration(format: .markdown)
            )

            // Run crawler
            let crawler = await DocumentationCrawler(configuration: config)

            let stats = try await crawler.crawl { progress in
                ConsoleLogger.output("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.currentURL.lastPathComponent)")
            }

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Crawl completed!")
            ConsoleLogger.info("   Total: \(stats.totalPages) pages")
            ConsoleLogger.info("   New: \(stats.newPages)")
            ConsoleLogger.info("   Updated: \(stats.updatedPages)")
            ConsoleLogger.info("   Skipped: \(stats.skippedPages)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
        }

        private func runEvolutionCrawl() async throws {
            let outputURL = URL(fileURLWithPath: outputDir ?? "~/.cupertino/swift-evolution").expandingTildeInPath

            let crawler = await SwiftEvolutionCrawler(
                outputDirectory: outputURL,
                onlyAccepted: onlyAccepted
            )

            let stats = try await crawler.crawl { progress in
                ConsoleLogger.output("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.proposalID)")
            }

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Download completed!")
            ConsoleLogger.info("   Total: \(stats.totalProposals) proposals")
            ConsoleLogger.info("   New: \(stats.newProposals)")
            ConsoleLogger.info("   Updated: \(stats.updatedProposals)")
            ConsoleLogger.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
        }
    }
}

// MARK: - Fetch Command

extension Cupertino {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Fetch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fetch resources without web crawling"
        )

        @Option(name: .long, help: "Type of resource to fetch: packages (Swift packages), code (Apple sample code)")
        var type: FetchType

        @Option(name: .long, help: "Output directory")
        var outputDir: String?

        @Option(name: .long, help: "Maximum number of items to fetch")
        var limit: Int?

        @Flag(name: .long, help: "Force re-download of existing files")
        var force: Bool = false

        @Flag(name: .long, help: "Resume from checkpoint if interrupted")
        var resume: Bool = false

        @Flag(name: .long, help: "Launch visible browser for authentication (code type only)")
        var authenticate: Bool = false

        mutating func run() async throws {
            ConsoleLogger.info("📦 Fetching \(type.displayName)\n")

            switch type {
            case .packages:
                try await runPackageFetch()
            case .code:
                try await runCodeFetch()
            }
        }

        private func runPackageFetch() async throws {
            let outputURL = URL(fileURLWithPath: outputDir ?? "~/.cupertino/packages").expandingTildeInPath

            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            if ProcessInfo.processInfo.environment["GITHUB_TOKEN"] == nil {
                ConsoleLogger.info("💡 Tip: Set GITHUB_TOKEN environment variable for higher rate limits")
                ConsoleLogger.info("   Without token: 60 requests/hour")
                ConsoleLogger.info("   With token: 5000 requests/hour")
                ConsoleLogger.info("   export GITHUB_TOKEN=your_token_here\n")
            }

            let fetcher = PackageFetcher(
                outputDirectory: outputURL,
                limit: limit,
                resume: resume
            )

            let stats = try await fetcher.fetch { progress in
                let percent = String(format: "%.1f", progress.percentage)
                ConsoleLogger.output("   Progress: \(percent)% - \(progress.packageName)")
            }

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Fetch completed!")
            ConsoleLogger.info("   Total packages: \(stats.totalPackages)")
            ConsoleLogger.info("   Successful: \(stats.successfulFetches)")
            ConsoleLogger.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
            ConsoleLogger.info("\n📁 Output: \(outputURL.path)/swift-packages-with-stars.json")
        }

        private func runCodeFetch() async throws {
            let outputURL = URL(fileURLWithPath: outputDir ?? "~/.cupertino/sample-code").expandingTildeInPath

            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            let crawler = await SampleCodeDownloader(
                outputDirectory: outputURL,
                maxSamples: limit,
                forceDownload: force,
                visibleBrowser: authenticate
            )

            let stats = try await crawler.download { progress in
                let percent = String(format: "%.1f", progress.percentage)
                ConsoleLogger.output("   Progress: \(percent)% - \(progress.sampleName)")
            }

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Download completed!")
            ConsoleLogger.info("   Total: \(stats.totalSamples) samples")
            ConsoleLogger.info("   Downloaded: \(stats.downloadedSamples)")
            ConsoleLogger.info("   Skipped: \(stats.skippedSamples)")
            ConsoleLogger.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
        }
    }
}

// MARK: - Index Command

extension Cupertino {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Index: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build FTS5 search index from crawled documentation"
        )

        @Option(name: .long, help: "Directory containing crawled documentation")
        var docsDir: String = "~/.cupertino/docs"

        @Option(name: .long, help: "Directory containing Swift Evolution proposals")
        var evolutionDir: String = "~/.cupertino/swift-evolution"

        @Option(name: .long, help: "Metadata file path")
        var metadataFile: String = "~/.cupertino/metadata.json"

        @Option(name: .long, help: "Search database path")
        var searchDB: String = "~/.cupertino/search.db"

        @Flag(name: .long, help: "Clear existing index before building")
        var clear: Bool = true

        mutating func run() async throws {
            ConsoleLogger.info("🔨 Building Search Index\n")

            // Expand paths
            let metadataURL = URL(fileURLWithPath: metadataFile).expandingTildeInPath
            let docsURL = URL(fileURLWithPath: docsDir).expandingTildeInPath
            let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
            let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

            // Check if metadata exists
            guard FileManager.default.fileExists(atPath: metadataURL.path) else {
                ConsoleLogger.info("❌ Metadata file not found: \(metadataURL.path)")
                ConsoleLogger.info("   Run 'cupertino crawl' first to download documentation.")
                throw ExitCode.failure
            }

            // Load metadata
            ConsoleLogger.info("📖 Loading metadata...")
            let metadata = try CrawlMetadata.load(from: metadataURL)
            ConsoleLogger.info("   Found \(metadata.pages.count) pages in metadata")

            // Initialize search index
            ConsoleLogger.info("🗄️  Initializing search database...")
            let searchIndex = try await SearchIndex(dbPath: searchDBURL)

            // Check if Evolution directory exists
            let hasEvolution = FileManager.default.fileExists(atPath: evolutionURL.path)
            let evolutionDirToUse = hasEvolution ? evolutionURL : nil

            if !hasEvolution {
                ConsoleLogger.info("ℹ️  Swift Evolution directory not found, skipping proposals")
                ConsoleLogger.info("   Run 'cupertino crawl --type evolution' to download proposals")
            }

            // Build index
            let builder = SearchIndexBuilder(
                searchIndex: searchIndex,
                metadata: metadata,
                docsDirectory: docsURL,
                evolutionDirectory: evolutionDirToUse
            )

            var lastPercent = 0.0
            try await builder.buildIndex(clearExisting: clear) { processed, total in
                let percent = Double(processed) / Double(total) * 100
                if percent - lastPercent >= 5.0 {
                    ConsoleLogger.output("   \(String(format: "%.0f%%", percent)) complete (\(processed)/\(total))")
                    lastPercent = percent
                }
            }

            // Show statistics
            let docCount = try await searchIndex.documentCount()
            let frameworks = try await searchIndex.listFrameworks()

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Search index built successfully!")
            ConsoleLogger.info("   Total documents: \(docCount)")
            ConsoleLogger.info("   Frameworks: \(frameworks.count)")
            ConsoleLogger.info("   Database: \(searchDBURL.path)")
            ConsoleLogger.info("   Size: \(formatFileSize(searchDBURL))")
            ConsoleLogger.info("\n💡 Tip: Start the MCP server with 'cupertino-mcp serve' to enable search")
        }

        private func formatFileSize(_ url: URL) -> String {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int64
            else {
                return "unknown"
            }

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: size)
        }
    }
}
