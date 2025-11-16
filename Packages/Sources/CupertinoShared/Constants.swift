import Foundation

// MARK: - Cupertino Constants

/// Global constants for Cupertino application
public enum CupertinoConstants {
    // MARK: - Directory Names

    /// Base directory name for Cupertino data
    public static let baseDirectoryName = ".cupertino"

    /// Subdirectory names
    public enum Directory {
        public static let docs = "docs"
        public static let swiftEvolution = "swift-evolution"
        public static let swiftOrg = "swift-org"
        public static let swiftBook = "swift-book"
        public static let packages = "packages"
        public static let sampleCode = "sample-code"
    }

    // MARK: - File Names

    public enum FileName {
        public static let metadata = "metadata.json"
        public static let config = "config.json"
        public static let searchDatabase = "search.db"
    }

    // MARK: - Default Paths

    /// Default base directory path: ~/.cupertino
    public static var defaultBaseDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(baseDirectoryName)
    }

    /// Default docs directory: ~/.cupertino/docs
    public static var defaultDocsDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.docs)
    }

    /// Default Swift Evolution directory: ~/.cupertino/swift-evolution
    public static var defaultSwiftEvolutionDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.swiftEvolution)
    }

    /// Default Swift.org directory: ~/.cupertino/swift-org
    public static var defaultSwiftOrgDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.swiftOrg)
    }

    /// Default Swift Book directory: ~/.cupertino/swift-book
    public static var defaultSwiftBookDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.swiftBook)
    }

    /// Default packages directory: ~/.cupertino/packages
    public static var defaultPackagesDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.packages)
    }

    /// Default sample code directory: ~/.cupertino/sample-code
    public static var defaultSampleCodeDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.sampleCode)
    }

    /// Default metadata file: ~/.cupertino/metadata.json
    public static var defaultMetadataFile: URL {
        defaultBaseDirectory.appendingPathComponent(FileName.metadata)
    }

    /// Default config file: ~/.cupertino/config.json
    public static var defaultConfigFile: URL {
        defaultBaseDirectory.appendingPathComponent(FileName.config)
    }

    /// Default search database: ~/.cupertino/search.db
    public static var defaultSearchDatabase: URL {
        defaultBaseDirectory.appendingPathComponent(FileName.searchDatabase)
    }

    // MARK: - Application Info

    public enum App {
        /// Application name
        public static let name = "Cupertino"

        /// Command name
        public static let commandName = "cupertino"

        /// MCP server name
        public static let mcpServerName = "cupertino"

        /// User agent for HTTP requests
        public static let userAgent = "CupertinoCrawler/1.0"

        /// Current version
        public static let version = "0.1.5"
    }

    // MARK: - Logging

    public enum Logging {
        /// Main subsystem identifier for logging
        public static let subsystem = "com.cupertino.cli"
    }
}
