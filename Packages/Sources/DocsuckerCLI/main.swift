import ArgumentParser
import DocsuckerCore
import DocsuckerLogging
import DocsuckerSearch
import DocsuckerShared
import Foundation

// MARK: - Docsucker CLI

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct AppleDocsucker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appledocsucker",
        abstract: "Apple Documentation Crawler",
        version: "0.1.5",
        subcommands: [Crawl.self, Resume.self, CrawlEvolution.self, DownloadSamples.self, ExportPDF.self, Update.self, BuildIndex.self, Config.self],
        defaultSubcommand: Crawl.self
    )
}

// MARK: - Crawl Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Crawl: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Crawl Apple documentation and save as Markdown"
        )

        @Option(name: .long, help: "Start URL to crawl from")
        var startURL: String = "https://developer.apple.com/documentation/"

        @Option(name: .long, help: "Maximum number of pages to crawl")
        var maxPages: Int = 15000

        @Option(name: .long, help: "Maximum depth to crawl")
        var maxDepth: Int = 15

        @Option(name: .long, help: "Output directory for documentation")
        var outputDir: String?

        @Option(name: .long, help: "Log file path (appends crawl progress)")
        var logFile: String?

        @Option(name: .long, help: "Allowed URL prefixes (comma-separated). If not specified, auto-detects based on start URL")
        var allowedPrefixes: String?

        @Flag(name: .long, help: "Force recrawl of all pages")
        var force: Bool = false

        @Flag(name: .long, help: "Resume from saved session (auto-detects and continues)")
        var resume: Bool = false

        mutating func run() async throws {
            if resume {
                ConsoleLogger.info("🔄 AppleDocsucker - Resuming from saved session\n")
            } else {
                ConsoleLogger.info("🚀 AppleDocsucker - Apple Documentation Crawler\n")
            }

            // Create configuration
            guard let startURL = URL(string: startURL) else {
                throw ValidationError("Invalid start URL: \(startURL)")
            }

            // Auto-detect output directory based on URL if not provided
            let defaultOutputDir: String
            if let outputDir {
                // Explicitly provided
                defaultOutputDir = outputDir
            } else {
                // Check for existing session to resume from
                // First check common default locations
                let homeDir = FileManager.default.homeDirectoryForCurrentUser
                let defaultCandidates = [
                    homeDir.appendingPathComponent(".docsucker/docs"),
                    homeDir.appendingPathComponent(".docsucker/swift-org"),
                    homeDir.appendingPathComponent(".docsucker/swift-book"),
                ]

                var foundSession: String?

                // Helper function to check a metadata file
                func checkMetadataFile(_ metadataFile: URL) -> String? {
                    guard FileManager.default.fileExists(atPath: metadataFile.path) else { return nil }
                    guard let data = try? Data(contentsOf: metadataFile),
                          let metadata = try? JSONDecoder().decode(CrawlMetadata.self, from: data),
                          let session = metadata.crawlState,
                          session.isActive,
                          session.startURL == startURL.absoluteString else { return nil }
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

                // If not found in defaults, check if metadata exists in other common crawl locations
                // This handles custom --output-dir cases by checking previously used directories
                if foundSession == nil {
                    let docsuckerDir = homeDir.appendingPathComponent(".docsucker")
                    if let contents = try? FileManager.default.contentsOfDirectory(
                        at: docsuckerDir,
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

                if let foundSession {
                    defaultOutputDir = foundSession
                } else if startURL.host?.contains("swift.org") == true {
                    defaultOutputDir = "~/.docsucker/swift-org"
                } else {
                    defaultOutputDir = "~/.docsucker/docs"
                }
            }

            let outputDirectory = URL(fileURLWithPath: defaultOutputDir).expandingTildeInPath

            // Parse allowed prefixes if provided
            let prefixes: [String]? = allowedPrefixes?.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }

            let config = DocsuckerConfiguration(
                crawler: CrawlerConfiguration(
                    startURL: startURL,
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
                // Progress callback - use output() for frequent updates (no logging)
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
    }
}

// MARK: - Resume Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Resume: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Resume an interrupted crawl from saved session"
        )

        @Option(name: .long, help: "Output directory to resume (auto-detects if not provided)")
        var outputDir: String?

        @Option(name: .long, help: "Maximum number of pages to crawl")
        var maxPages: Int?

        @Option(name: .long, help: "Maximum crawl depth")
        var maxDepth: Int?

        mutating func run() async throws {
            ConsoleLogger.info("🔄 Resume Crawl\n")

            // Determine output directory
            let outputURL: URL
            if let outputDir {
                outputURL = URL(fileURLWithPath: outputDir).expandingTildeInPath
            } else {
                // Scan common directories for active sessions
                let homeDir = FileManager.default.homeDirectoryForCurrentUser
                let candidates = [
                    homeDir.appendingPathComponent(".docsucker/docs"),
                    homeDir.appendingPathComponent(".docsucker/swift-org"),
                    homeDir.appendingPathComponent(".docsucker/swift-book"),
                ]

                var foundSessions: [(URL, URL)] = [] // (outputDir, metadataFile)
                for candidate in candidates {
                    let metadataFile = candidate.appendingPathComponent("metadata.json")
                    if FileManager.default.fileExists(atPath: metadataFile.path) {
                        foundSessions.append((candidate, metadataFile))
                    }
                }

                if foundSessions.isEmpty {
                    ConsoleLogger.error("❌ No active crawl sessions found")
                    ConsoleLogger.info("Searched in:")
                    for candidate in candidates {
                        ConsoleLogger.info("  • \(candidate.path)")
                    }
                    throw ExitCode.failure
                }

                if foundSessions.count == 1 {
                    outputURL = foundSessions[0].0
                    ConsoleLogger.info("Found session: \(outputURL.lastPathComponent)")
                } else {
                    ConsoleLogger.info("Multiple sessions found:")
                    for (index, (dir, _)) in foundSessions.enumerated() {
                        ConsoleLogger.info("  \(index + 1). \(dir.lastPathComponent) (\(dir.path))")
                    }
                    ConsoleLogger.error("❌ Please specify --output-dir to choose which session to resume")
                    throw ExitCode.failure
                }
            }

            // Load metadata to get the start URL
            let metadataFile = outputURL.appendingPathComponent("metadata.json")
            guard FileManager.default.fileExists(atPath: metadataFile.path) else {
                ConsoleLogger.error("❌ No metadata.json found in \(outputURL.path)")
                ConsoleLogger.info("This directory has no saved crawl session to resume")
                throw ExitCode.failure
            }

            // Read metadata to extract start URL
            let metadataData = try Data(contentsOf: metadataFile)
            let metadata = try JSONDecoder().decode(CrawlMetadata.self, from: metadataData)

            guard let crawlState = metadata.crawlState else {
                ConsoleLogger.error("❌ No crawl state found in metadata")
                throw ExitCode.failure
            }

            guard let startURL = URL(string: crawlState.startURL) else {
                ConsoleLogger.error("❌ Invalid start URL: \(crawlState.startURL)")
                throw ExitCode.failure
            }

            ConsoleLogger.info("Resuming crawl:")
            ConsoleLogger.info("  Start URL: \(startURL.absoluteString)")
            ConsoleLogger.info("  Output: \(outputURL.path)")
            ConsoleLogger.info("  Visited: \(crawlState.visited.count) pages")
            ConsoleLogger.info("  Queued: \(crawlState.queue.count) pages")
            ConsoleLogger.output("")

            // Create configuration
            let config = DocsuckerConfiguration(
                crawler: CrawlerConfiguration(
                    startURL: startURL,
                    maxPages: maxPages ?? 15000,
                    maxDepth: maxDepth ?? 15,
                    outputDirectory: outputURL
                ),
                changeDetection: ChangeDetectionConfiguration(
                    forceRecrawl: false,
                    outputDirectory: outputURL
                ),
                output: OutputConfiguration(format: .markdown)
            )

            // Create and run crawler (will auto-resume from saved state)
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
    }
}

// MARK: - Crawl Evolution Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct CrawlEvolution: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "crawl-evolution",
            abstract: "Download Swift Evolution proposals from GitHub"
        )

        @Option(name: .long, help: "Output directory for proposals")
        var outputDir: String = "~/.docsucker/swift-evolution"

        @Flag(name: .long, help: "Only download accepted/implemented proposals")
        var onlyAccepted: Bool = false

        mutating func run() async throws {
            ConsoleLogger.info("🚀 Swift Evolution Crawler\n")

            let outputURL = URL(fileURLWithPath: outputDir).expandingTildeInPath

            // Create crawler
            let crawler = await SwiftEvolutionCrawler(
                outputDirectory: outputURL,
                onlyAccepted: onlyAccepted
            )

            // Run crawler
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

// MARK: - Download Samples Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct DownloadSamples: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "download-samples",
            abstract: "Download Apple sample code projects (zip/tar files)"
        )

        @Option(name: .long, help: "Output directory for sample code files")
        var outputDir: String = "~/.docsucker/sample-code"

        @Option(name: .long, help: "Maximum number of samples to download")
        var maxSamples: Int?

        @Flag(name: .long, help: "Force re-download of existing files")
        var force: Bool = false

        @Flag(name: .long, help: "Launch visible browser for authentication (sign in to Apple Developer)")
        var authenticate: Bool = false

        mutating func run() async throws {
            ConsoleLogger.info("🚀 Sample Code Downloader\n")

            let outputURL = URL(fileURLWithPath: outputDir).expandingTildeInPath

            // Create output directory if needed
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            // Create crawler
            let crawler = await SampleCodeDownloader(
                outputDirectory: outputURL,
                maxSamples: maxSamples,
                forceDownload: force,
                visibleBrowser: authenticate
            )

            // Run crawler
            let stats = try await crawler.download { progress in
                ConsoleLogger.output("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.sampleName)")
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

// MARK: - Export PDF Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct ExportPDF: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "export-pdf",
            abstract: "Export markdown documentation to PDF format"
        )

        @Option(name: .long, help: "Input directory containing markdown files")
        var inputDir: String = "~/.docsucker/docs"

        @Option(name: .long, help: "Output directory for PDF files")
        var outputDir: String = "~/.docsucker/pdfs"

        @Option(name: .long, help: "Maximum number of files to convert")
        var maxFiles: Int?

        @Flag(name: .long, help: "Force re-export of existing PDFs")
        var force: Bool = false

        mutating func run() async throws {
            ConsoleLogger.info("📄 PDF Exporter\n")

            let inputURL = URL(fileURLWithPath: inputDir).expandingTildeInPath
            let outputURL = URL(fileURLWithPath: outputDir).expandingTildeInPath

            // Create output directory
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            // Create exporter
            let exporter = await PDFExporter(
                inputDirectory: inputURL,
                outputDirectory: outputURL,
                maxFiles: maxFiles,
                forceExport: force
            )

            // Run export
            let stats = try await exporter.export { progress in
                ConsoleLogger.output("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.fileName)")
            }

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Export completed!")
            ConsoleLogger.info("   Total: \(stats.totalFiles) files")
            ConsoleLogger.info("   Exported: \(stats.exportedFiles)")
            ConsoleLogger.info("   Skipped: \(stats.skippedFiles)")
            ConsoleLogger.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
        }
    }
}

// MARK: - Update Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update existing documentation (incremental crawl)"
        )

        @Option(name: .long, help: "Output directory for documentation")
        var outputDir: String = "~/.docsucker/docs"

        mutating func run() async throws {
            ConsoleLogger.info("🔄 AppleDocsucker - Incremental Update\n")

            // Load configuration
            let configURL = URL(fileURLWithPath: "~/.docsucker/config.json").expandingTildeInPath
            let config: DocsuckerConfiguration

            if FileManager.default.fileExists(atPath: configURL.path) {
                config = try DocsuckerConfiguration.load(from: configURL)
            } else {
                // Use default configuration
                config = DocsuckerConfiguration(
                    crawler: CrawlerConfiguration(
                        outputDirectory: URL(fileURLWithPath: outputDir).expandingTildeInPath
                    )
                )
            }

            // Run crawler
            let crawler = await DocumentationCrawler(configuration: config)
            let stats = try await crawler.crawl()

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Update completed!")
            ConsoleLogger.info("   Total: \(stats.totalPages) pages")
            ConsoleLogger.info("   New: \(stats.newPages)")
            ConsoleLogger.info("   Updated: \(stats.updatedPages)")
            ConsoleLogger.info("   Skipped: \(stats.skippedPages)")
        }
    }
}

// MARK: - Build Index Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct BuildIndex: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build-index",
            abstract: "Build search index from crawled documentation"
        )

        @Option(name: .long, help: "Directory containing crawled documentation")
        var docsDir: String = "~/.docsucker/docs"

        @Option(name: .long, help: "Directory containing Swift Evolution proposals")
        var evolutionDir: String = "~/.docsucker/swift-evolution"

        @Option(name: .long, help: "Metadata file path")
        var metadataFile: String = "~/.docsucker/metadata.json"

        @Option(name: .long, help: "Search database path")
        var searchDB: String = "~/.docsucker/search.db"

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
                ConsoleLogger.info("   Run 'appledocsucker crawl' first to download documentation.")
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
                ConsoleLogger.info("   Run 'appledocsucker crawl-evolution' to download proposals")
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
            ConsoleLogger.info("\n💡 Tip: Start the MCP server with 'appledocsucker-mcp serve' to enable search")
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

// MARK: - Config Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage Docsucker configuration",
            subcommands: [Show.self, Init.self]
        )

        @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
        struct Show: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show current configuration"
            )

            func run() async throws {
                let configURL = URL(fileURLWithPath: "~/.docsucker/config.json").expandingTildeInPath

                if FileManager.default.fileExists(atPath: configURL.path) {
                    let config = try DocsuckerConfiguration.load(from: configURL)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(config)
                    if let json = String(data: data, encoding: .utf8) {
                        print(json)
                    }
                } else {
                    ConsoleLogger.info("No configuration file found at: \(configURL.path)")
                    ConsoleLogger.info("Run 'appledocsucker config init' to create one.")
                }
            }
        }

        @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
        struct Init: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Initialize default configuration"
            )

            func run() async throws {
                let configURL = URL(fileURLWithPath: "~/.docsucker/config.json").expandingTildeInPath

                if FileManager.default.fileExists(atPath: configURL.path) {
                    ConsoleLogger.info("⚠️  Configuration file already exists at: \(configURL.path)")
                    ConsoleLogger.info("   Delete it first if you want to recreate.")
                } else {
                    let config = DocsuckerConfiguration()
                    try config.save(to: configURL)
                    ConsoleLogger.info("✅ Configuration created at: \(configURL.path)")
                }
            }
        }
    }
}
