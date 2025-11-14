// swift-tools-version: 6.0

import PackageDescription

// -------------------------------------------------------------

// MARK: Products

// -------------------------------------------------------------

let baseProducts: [Product] = [
    // MCP Framework (cross-platform)
    .singleTargetLibrary("MCPShared"),
    .singleTargetLibrary("MCPTransport"),
    .singleTargetLibrary("MCPServer"),
]

// Docsucker products (macOS only - uses FileManager.homeDirectoryForCurrentUser)
#if os(macOS)
let macOSOnlyProducts: [Product] = [
    .singleTargetLibrary("DocsuckerShared"),
    .singleTargetLibrary("DocsuckerCore"),
    .singleTargetLibrary("DocsuckerMCPSupport"),
    .executable(name: "docsucker", targets: ["DocsuckerCLI"]),
    .executable(name: "docsucker-mcp", targets: ["DocsuckerMCP"]),
]
#else
let macOSOnlyProducts: [Product] = []
#endif

let allProducts = baseProducts + macOSOnlyProducts

// -------------------------------------------------------------

// MARK: Dependencies

// -------------------------------------------------------------

let deps: [Package.Dependency] = [
    // Swift Argument Parser (cross-platform CLI tool)
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
]

// -------------------------------------------------------------

// MARK: Targets

// -------------------------------------------------------------

let targets: [Target] = {
    // ---------- MCP Framework (Foundation → Infrastructure) ----------
    let mcpSharedTarget = Target.target(
        name: "MCPShared",
        dependencies: []
    )
    let mcpSharedTestsTarget = Target.testTarget(
        name: "MCPSharedTests",
        dependencies: ["MCPShared"]
    )

    let mcpTransportTarget = Target.target(
        name: "MCPTransport",
        dependencies: ["MCPShared"]
    )
    let mcpTransportTestsTarget = Target.testTarget(
        name: "MCPTransportTests",
        dependencies: ["MCPTransport"]
    )

    let mcpServerTarget = Target.target(
        name: "MCPServer",
        dependencies: ["MCPShared", "MCPTransport"]
    )
    let mcpServerTestsTarget = Target.testTarget(
        name: "MCPServerTests",
        dependencies: ["MCPServer"]
    )

    let mcpTargets = [
        mcpSharedTarget,
        mcpSharedTestsTarget,
        mcpTransportTarget,
        mcpTransportTestsTarget,
        mcpServerTarget,
        mcpServerTestsTarget,
    ]

    // ---------- Docsucker (Apple Docs Crawler → MCP Server - macOS only) ----------
    #if os(macOS)
    let docsuckerSharedTarget = Target.target(
        name: "DocsuckerShared",
        dependencies: ["MCPShared"]
    )
    let docsuckerSharedTestsTarget = Target.testTarget(
        name: "DocsuckerSharedTests",
        dependencies: ["DocsuckerShared"]
    )

    let docsuckerCoreTarget = Target.target(
        name: "DocsuckerCore",
        dependencies: ["DocsuckerShared"]
    )
    let docsuckerCoreTestsTarget = Target.testTarget(
        name: "DocsuckerCoreTests",
        dependencies: ["DocsuckerCore"]
    )

    let docsuckerMCPSupportTarget = Target.target(
        name: "DocsuckerMCPSupport",
        dependencies: ["MCPServer", "MCPShared", "DocsuckerShared"]
    )
    let docsuckerMCPSupportTestsTarget = Target.testTarget(
        name: "DocsuckerMCPSupportTests",
        dependencies: ["DocsuckerMCPSupport"]
    )

    let docsuckerCLITarget = Target.executableTarget(
        name: "DocsuckerCLI",
        dependencies: [
            "DocsuckerShared",
            "DocsuckerCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    let docsuckerMCPTarget = Target.executableTarget(
        name: "DocsuckerMCP",
        dependencies: [
            "MCPServer",
            "MCPTransport",
            "DocsuckerShared",
            "DocsuckerCore",
            "DocsuckerMCPSupport",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    let docsuckerTargets: [Target] = [
        docsuckerSharedTarget,
        docsuckerSharedTestsTarget,
        docsuckerCoreTarget,
        docsuckerCoreTestsTarget,
        docsuckerMCPSupportTarget,
        docsuckerMCPSupportTestsTarget,
        docsuckerCLITarget,
        docsuckerMCPTarget,
    ]
    #else
    let docsuckerTargets: [Target] = []
    #endif

    return mcpTargets + docsuckerTargets
}()

// -------------------------------------------------------------

// MARK: Package

// -------------------------------------------------------------

let package = Package(
    name: "Docsucker",
    platforms: [
        .macOS(.v15),
    ],
    products: allProducts,
    dependencies: deps,
    targets: targets
)

// -------------------------------------------------------------

// MARK: Helper

// -------------------------------------------------------------

extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}
