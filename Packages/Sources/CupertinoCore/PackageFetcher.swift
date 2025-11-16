import CupertinoLogging
import Foundation

// MARK: - Package Fetcher

/// Fetches Swift packages from SwiftPackageIndex and enriches with GitHub metadata
public actor PackageFetcher {
    private let packageListURL = URL(string: "https://raw.githubusercontent.com/SwiftPackageIndex/PackageList/main/packages.json")!
    private let outputDirectory: URL
    private let limit: Int?
    private let resumeFromCheckpoint: Bool
    private var starCache: [String: Int] = [:] // Cache star counts to avoid double-fetching

    public init(outputDirectory: URL, limit: Int? = nil, resume: Bool = false) {
        self.outputDirectory = outputDirectory
        self.limit = limit
        resumeFromCheckpoint = resume
    }

    // MARK: - Public API

    /// Fetch packages and enrich with GitHub metadata
    public func fetch(onProgress: ((PackageFetchProgress) -> Void)? = nil) async throws -> PackageFetchStatistics {
        var stats = PackageFetchStatistics(startTime: Date())

        logInfo("📦 Fetching Swift packages from SwiftPackageIndex...")
        logInfo("   Package list: \(packageListURL.absoluteString)")
        logInfo("   Output: \(outputDirectory.path)")

        // Create output directory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // Download package list
        logInfo("\n📥 Downloading package list...")
        var packageURLs = try await downloadPackageList()
        logInfo("   Found \(packageURLs.count) packages")

        // Quick pre-fetch: Get star counts for all packages first (lightweight)
        logInfo("\n⭐ Pre-fetching star counts to sort by popularity...")
        packageURLs = try await sortPackagesByStars(packageURLs)
        logInfo("   ✓ Packages sorted by star count (most popular first)")

        // Load checkpoint if resuming
        var packages: [PackageInfo] = []
        var startIndex = 0

        if resumeFromCheckpoint {
            if let checkpoint = try? loadCheckpoint() {
                packages = checkpoint.packages
                startIndex = checkpoint.processedCount
                logInfo("📂 Resuming from checkpoint: \(startIndex) packages processed")
            }
        }

        // Determine how many to process
        let totalToProcess = limit.map { min($0, packageURLs.count) } ?? packageURLs.count
        logInfo("\n🔍 Fetching metadata for \(totalToProcess) packages...\n")

        // Fetch metadata for each package
        var rateLimited = false

        for index in startIndex..<totalToProcess {
            let packageURL = packageURLs[index]

            guard let (owner, repo) = extractOwnerRepo(from: packageURL) else {
                logError("Invalid package URL: \(packageURL)")
                stats.errors += 1
                continue
            }

            // Progress logging
            if (index + 1) % 100 == 0 {
                logInfo("\n[\(index + 1)/\(totalToProcess)] Fetching \(owner)/\(repo)...")
                logInfo("   💾 Saving checkpoint...")
                try? saveCheckpoint(packages: packages, processedCount: index + 1)
            } else if (index + 1) % 10 == 0 {
                logInfo("[\(index + 1)/\(totalToProcess)] \(owner)/\(repo)")
            }

            // Fetch GitHub metadata
            let packageInfo: PackageInfo
            do {
                packageInfo = try await fetchGitHubMetadata(owner: owner, repo: repo)
                packages.append(packageInfo)
                stats.successfulFetches += 1
            } catch PackageFetchError.rateLimited {
                logError("\n⚠️  Rate limited at package \(index + 1)/\(totalToProcess)")
                logInfo("   💾 Checkpoint saved")
                logInfo("   ⏸️  Wait 60 minutes or use GitHub token for higher limits")
                rateLimited = true
                try? saveCheckpoint(packages: packages, processedCount: index)
                break
            } catch PackageFetchError.notFound {
                // Package deleted/moved - save with minimal info
                packages.append(PackageInfo(
                    owner: owner,
                    repo: repo,
                    stars: 0,
                    description: nil,
                    url: "https://github.com/\(owner)/\(repo)",
                    archived: false,
                    fork: false,
                    updatedAt: nil,
                    language: nil,
                    license: nil,
                    error: "not_found"
                ))
                stats.errors += 1
            } catch {
                logError("Failed to fetch \(owner)/\(repo): \(error)")
                packages.append(PackageInfo(
                    owner: owner,
                    repo: repo,
                    stars: 0,
                    description: nil,
                    url: "https://github.com/\(owner)/\(repo)",
                    archived: false,
                    fork: false,
                    updatedAt: nil,
                    language: nil,
                    license: nil,
                    error: "fetch_failed"
                ))
                stats.errors += 1
            }

            // Progress callback
            if let onProgress {
                let progress = PackageFetchProgress(
                    current: index + 1,
                    total: totalToProcess,
                    packageName: "\(owner)/\(repo)",
                    stats: stats
                )
                onProgress(progress)
            }

            // Rate limiting: 1 request per second
            if (index + 1) % 50 == 0 {
                try await Task.sleep(for: .seconds(5)) // Extra pause every 50
            } else {
                try await Task.sleep(for: .seconds(1.2))
            }
        }

        // Save final checkpoint
        if !rateLimited {
            try? saveCheckpoint(packages: packages, processedCount: totalToProcess)
        }

        // Sort by stars (descending)
        let sortedPackages = packages
            .filter { $0.error == nil || $0.stars > 0 }
            .sorted { $0.stars > $1.stars }

        // Save results
        let output = PackageFetchOutput(
            totalPackages: sortedPackages.count,
            totalProcessed: packages.count,
            errors: stats.errors,
            generatedAt: Date(),
            packages: sortedPackages
        )

        let outputFile = outputDirectory.appendingPathComponent("swift-packages-with-stars.json")
        try saveJSON(output, to: outputFile)

        stats.endTime = Date()
        stats.totalPackages = sortedPackages.count

        logInfo("\n✅ Fetch completed!")
        logInfo("   Total packages: \(sortedPackages.count)")
        logInfo("   Successful: \(stats.successfulFetches)")
        logInfo("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            logInfo("   Duration: \(Int(duration))s")
        }
        logInfo("\n📁 Output: \(outputFile.path)")

        // Show top 20
        logInfo("\nTop 20 packages by stars:")
        for (index, pkg) in sortedPackages.prefix(20).enumerated() {
            let archived = pkg.archived ? " [ARCHIVED]" : ""
            let fork = pkg.fork ? " [FORK]" : ""
            logInfo(String(
                format: "  %2d. %-50s ⭐ %6d%@%@",
                index + 1,
                "\(pkg.owner)/\(pkg.repo)",
                pkg.stars,
                archived,
                fork
            ))
        }

        return stats
    }

    // MARK: - Private Methods

    private func sortPackagesByStars(_ packageURLs: [String]) async throws -> [String] {
        // Quick fetch: only get star counts (much lighter than full metadata)
        var packageStars: [(url: String, stars: Int)] = []

        for (index, url) in packageURLs.enumerated() {
            guard let (owner, repo) = extractOwnerRepo(from: url) else {
                packageStars.append((url, 0))
                continue
            }

            // Progress every 100
            if (index + 1) % 100 == 0 {
                logInfo("   [\(index + 1)/\(packageURLs.count)] Fetched star counts...")
            }

            // Fetch only stars (lightweight)
            do {
                let stars = try await fetchStarCount(owner: owner, repo: repo)
                packageStars.append((url, stars))

                // Cache the star count for later reuse
                starCache["\(owner)/\(repo)"] = stars
            } catch {
                packageStars.append((url, 0))
                starCache["\(owner)/\(repo)"] = 0
            }

            // Rate limiting
            if (index + 1) % 50 == 0 {
                try await Task.sleep(for: .seconds(2))
            } else {
                try await Task.sleep(for: .seconds(0.5))
            }
        }

        // Sort by stars descending
        return packageStars.sorted { $0.stars > $1.stars }.map(\.url)
    }

    private func fetchStarCount(owner: String, repo: String) async throws -> Int {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue(CupertinoConstants.App.userAgent, forHTTPHeaderField: "User-Agent")

        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return 0
        }

        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let stars = json["stargazers_count"] as? Int {
                return stars
            }
        }

        return 0
    }

    private func downloadPackageList() async throws -> [String] {
        let (data, _) = try await URLSession.shared.data(from: packageListURL)
        return try JSONDecoder().decode([String].self, from: data)
    }

    private func extractOwnerRepo(from githubURL: String) -> (String, String)? {
        // Match: https://github.com/owner/repo.git or https://github.com/owner/repo
        let pattern = #"https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: githubURL, range: NSRange(githubURL.startIndex..., in: githubURL)),
              let ownerRange = Range(match.range(at: 1), in: githubURL),
              let repoRange = Range(match.range(at: 2), in: githubURL)
        else {
            return nil
        }

        return (String(githubURL[ownerRange]), String(githubURL[repoRange]))
    }

    private func fetchGitHubMetadata(owner: String, repo: String) async throws -> PackageInfo {
        let cacheKey = "\(owner)/\(repo)"

        // Check if we already have star count cached from sorting phase
        if let cachedStars = starCache[cacheKey] {
            // We have stars cached, but still need other metadata (description, language, etc.)
            // Fetch full metadata but we could skip if stars is all we need
            let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!

            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue(CupertinoConstants.App.userAgent, forHTTPHeaderField: "User-Agent")

            if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PackageFetchError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let repoData = try decoder.decode(GitHubRepository.self, from: data)

                // Use cached stars instead of refetching
                return PackageInfo(
                    owner: owner,
                    repo: repo,
                    stars: cachedStars, // Use cached value!
                    description: repoData.description,
                    url: repoData.htmlUrl,
                    archived: repoData.archived,
                    fork: repoData.fork,
                    updatedAt: repoData.updatedAt,
                    language: repoData.language,
                    license: repoData.license?.spdxId
                )

            case 404:
                throw PackageFetchError.notFound

            case 403:
                if let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
                   let remainingInt = Int(remaining),
                   remainingInt == 0 {
                    throw PackageFetchError.rateLimited
                }
                throw PackageFetchError.forbidden

            default:
                throw PackageFetchError.httpError(httpResponse.statusCode)
            }
        } else {
            // No cache, fetch everything (shouldn't happen after sorting, but handle it)
            let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!

            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue(CupertinoConstants.App.userAgent, forHTTPHeaderField: "User-Agent")

            if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PackageFetchError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let repoData = try decoder.decode(GitHubRepository.self, from: data)

                return PackageInfo(
                    owner: owner,
                    repo: repo,
                    stars: repoData.stargazersCount,
                    description: repoData.description,
                    url: repoData.htmlUrl,
                    archived: repoData.archived,
                    fork: repoData.fork,
                    updatedAt: repoData.updatedAt,
                    language: repoData.language,
                    license: repoData.license?.spdxId
                )

            case 404:
                throw PackageFetchError.notFound

            case 403:
                if let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
                   let remainingInt = Int(remaining),
                   remainingInt == 0 {
                    throw PackageFetchError.rateLimited
                }
                throw PackageFetchError.forbidden

            default:
                throw PackageFetchError.httpError(httpResponse.statusCode)
            }
        }
    }

    private func loadCheckpoint() throws -> PackageFetchCheckpoint {
        let checkpointFile = outputDirectory.appendingPathComponent("checkpoint.json")
        let data = try Data(contentsOf: checkpointFile)
        return try JSONDecoder().decode(PackageFetchCheckpoint.self, from: data)
    }

    private func saveCheckpoint(packages: [PackageInfo], processedCount: Int) throws {
        let checkpoint = PackageFetchCheckpoint(
            processedCount: processedCount,
            packages: packages,
            timestamp: Date()
        )
        let checkpointFile = outputDirectory.appendingPathComponent("checkpoint.json")
        try saveJSON(checkpoint, to: checkpointFile)
    }

    private func saveJSON(_ value: some Encodable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    // MARK: - Logging

    private func logInfo(_ message: String) {
        CupertinoLogger.crawler.info(message)
        print(message)
    }

    private func logError(_ message: String) {
        CupertinoLogger.crawler.error(message)
        fputs("\(message)\n", stderr)
    }
}

// MARK: - Models

public struct PackageInfo: Codable, Sendable {
    public let owner: String
    public let repo: String
    public let stars: Int
    public let description: String?
    public let url: String
    public let archived: Bool
    public let fork: Bool
    public let updatedAt: String?
    public let language: String?
    public let license: String?
    public let error: String?

    public init(
        owner: String,
        repo: String,
        stars: Int,
        description: String?,
        url: String,
        archived: Bool,
        fork: Bool,
        updatedAt: String?,
        language: String?,
        license: String?,
        error: String? = nil
    ) {
        self.owner = owner
        self.repo = repo
        self.stars = stars
        self.description = description
        self.url = url
        self.archived = archived
        self.fork = fork
        self.updatedAt = updatedAt
        self.language = language
        self.license = license
        self.error = error
    }
}

public struct PackageFetchOutput: Codable, Sendable {
    public let totalPackages: Int
    public let totalProcessed: Int
    public let errors: Int
    public let generatedAt: Date
    public let packages: [PackageInfo]
}

public struct PackageFetchCheckpoint: Codable, Sendable {
    public let processedCount: Int
    public let packages: [PackageInfo]
    public let timestamp: Date
}

public struct PackageFetchStatistics: Sendable {
    public var totalPackages: Int = 0
    public var successfulFetches: Int = 0
    public var errors: Int = 0
    public var startTime: Date?
    public var endTime: Date?

    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
}

public struct PackageFetchProgress: Sendable {
    public let current: Int
    public let total: Int
    public let packageName: String
    public let stats: PackageFetchStatistics

    public var percentage: Double {
        Double(current) / Double(total) * 100
    }
}

// MARK: - GitHub API Models

private struct GitHubRepository: Codable {
    let stargazersCount: Int
    let description: String?
    let htmlUrl: String
    let archived: Bool
    let fork: Bool
    let updatedAt: String
    let language: String?
    let license: GitHubLicense?
}

private struct GitHubLicense: Codable {
    let spdxId: String
}

// MARK: - Errors

enum PackageFetchError: Error {
    case rateLimited
    case notFound
    case forbidden
    case invalidResponse
    case httpError(Int)
}
