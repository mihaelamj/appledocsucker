import ArgumentParser
import Foundation

// MARK: - Supporting Types

extension Cupertino {
    enum CrawlType: String, ExpressibleByArgument {
        case docs
        case swift
        case evolution
        case packages
        case all

        var displayName: String {
            switch self {
            case .docs: return "Apple Documentation"
            case .swift: return "Swift.org Documentation"
            case .evolution: return "Swift Evolution Proposals"
            case .packages: return "Swift Package Documentation"
            case .all: return "All Documentation"
            }
        }

        var defaultURL: String {
            switch self {
            case .docs: return "https://developer.apple.com/documentation/"
            case .swift: return "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/"
            case .evolution: return "" // N/A - uses different crawler
            case .packages: return "" // Package documentation not yet implemented
            case .all: return "" // N/A - crawls all types sequentially
            }
        }

        var defaultOutputDir: String {
            switch self {
            case .docs: return "~/.cupertino/docs"
            case .swift: return "~/.cupertino/swift-org"
            case .evolution: return "~/.cupertino/swift-evolution"
            case .packages: return "~/.cupertino/packages"
            case .all: return "~/.cupertino" // Parent directory
            }
        }

        static var allTypes: [CrawlType] {
            [.docs, .swift, .evolution]
        }
    }

    enum FetchType: String, ExpressibleByArgument {
        case packages
        case code

        var displayName: String {
            switch self {
            case .packages: return "Swift Package Metadata"
            case .code: return "Apple Sample Code"
            }
        }
    }
}
