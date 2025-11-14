# Makefile for Docsucker
# Apple Documentation Crawler & MCP Server

# Configuration
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
BUILD_DIR = .build
SWIFT = swift
INSTALL = install

# Build configuration
SWIFT_BUILD_FLAGS = -c release
PRODUCT_NAME_CLI = docsucker
PRODUCT_NAME_MCP = docsucker-mcp

# Detect architecture
ARCH := $(shell uname -m)
ifeq ($(ARCH),arm64)
    SWIFT_ARCH = arm64-apple-macosx
else
    SWIFT_ARCH = x86_64-apple-macosx
endif

# Colors for output
BOLD := $(shell tput bold)
GREEN := $(shell tput setaf 2)
YELLOW := $(shell tput setaf 3)
RESET := $(shell tput sgr0)

.PHONY: all build build-debug build-release install uninstall test clean help

# Default target
all: build

## help: Show this help message
help:
	@echo "$(BOLD)Docsucker - Makefile Help$(RESET)"
	@echo ""
	@echo "$(BOLD)Available targets:$(RESET)"
	@echo "  $(GREEN)make build$(RESET)         - Build both executables (release mode)"
	@echo "  $(GREEN)make build-debug$(RESET)   - Build both executables (debug mode)"
	@echo "  $(GREEN)make build-release$(RESET) - Build both executables (release mode, optimized)"
	@echo "  $(GREEN)make install$(RESET)       - Install executables to $(BINDIR)"
	@echo "  $(GREEN)make uninstall$(RESET)     - Remove installed executables"
	@echo "  $(GREEN)make test$(RESET)          - Run all tests"
	@echo "  $(GREEN)make test-unit$(RESET)     - Run unit tests only (skip integration)"
	@echo "  $(GREEN)make test-integration$(RESET) - Run integration tests only"
	@echo "  $(GREEN)make clean$(RESET)         - Clean build artifacts"
	@echo "  $(GREEN)make distclean$(RESET)     - Clean everything including Package.resolved"
	@echo "  $(GREEN)make format$(RESET)        - Format Swift code (requires swift-format)"
	@echo "  $(GREEN)make lint$(RESET)          - Lint Swift code (requires SwiftLint)"
	@echo "  $(GREEN)make archive$(RESET)       - Create release archive (.tar.gz)"
	@echo "  $(GREEN)make bottle$(RESET)        - Create Homebrew bottle"
	@echo ""
	@echo "$(BOLD)Configuration:$(RESET)"
	@echo "  PREFIX=$(PREFIX)"
	@echo "  BINDIR=$(BINDIR)"
	@echo "  ARCH=$(ARCH)"
	@echo ""
	@echo "$(BOLD)Examples:$(RESET)"
	@echo "  # Build and install"
	@echo "  make build"
	@echo "  sudo make install"
	@echo ""
	@echo "  # Install to custom location"
	@echo "  make install PREFIX=~/.local"
	@echo ""
	@echo "  # Build debug version"
	@echo "  make build-debug"
	@echo ""
	@echo "  # Run tests"
	@echo "  make test"

## build: Build both executables (release mode)
build: build-release

## build-debug: Build in debug mode
build-debug:
	@echo "$(BOLD)$(GREEN)Building Docsucker (debug)...$(RESET)"
	$(SWIFT) build --product $(PRODUCT_NAME_CLI)
	$(SWIFT) build --product $(PRODUCT_NAME_MCP)
	@echo "$(GREEN)✓ Build complete$(RESET)"
	@echo "  CLI: $(BUILD_DIR)/debug/$(PRODUCT_NAME_CLI)"
	@echo "  MCP: $(BUILD_DIR)/debug/$(PRODUCT_NAME_MCP)"

## build-release: Build in release mode (optimized)
build-release:
	@echo "$(BOLD)$(GREEN)Building Docsucker (release)...$(RESET)"
	$(SWIFT) build $(SWIFT_BUILD_FLAGS) --product $(PRODUCT_NAME_CLI)
	$(SWIFT) build $(SWIFT_BUILD_FLAGS) --product $(PRODUCT_NAME_MCP)
	@echo "$(GREEN)✓ Build complete$(RESET)"
	@echo "  CLI: $(BUILD_DIR)/release/$(PRODUCT_NAME_CLI)"
	@echo "  MCP: $(BUILD_DIR)/release/$(PRODUCT_NAME_MCP)"

## install: Install executables to PREFIX/bin (requires sudo if PREFIX=/usr/local)
install: build-release
	@echo "$(BOLD)$(GREEN)Installing to $(BINDIR)...$(RESET)"
	@mkdir -p $(BINDIR)
	$(INSTALL) -m 755 $(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) $(BINDIR)/$(PRODUCT_NAME_CLI)
	$(INSTALL) -m 755 $(BUILD_DIR)/release/$(PRODUCT_NAME_MCP) $(BINDIR)/$(PRODUCT_NAME_MCP)
	@echo "$(GREEN)✓ Installation complete$(RESET)"
	@echo "  Installed: $(BINDIR)/$(PRODUCT_NAME_CLI)"
	@echo "  Installed: $(BINDIR)/$(PRODUCT_NAME_MCP)"
	@echo ""
	@echo "$(YELLOW)Verify installation:$(RESET)"
	@echo "  $(PRODUCT_NAME_CLI) --version"
	@echo "  $(PRODUCT_NAME_MCP) --version"

## uninstall: Remove installed executables
uninstall:
	@echo "$(BOLD)$(YELLOW)Uninstalling from $(BINDIR)...$(RESET)"
	rm -f $(BINDIR)/$(PRODUCT_NAME_CLI)
	rm -f $(BINDIR)/$(PRODUCT_NAME_MCP)
	@echo "$(GREEN)✓ Uninstall complete$(RESET)"

## test: Run all tests
test:
	@echo "$(BOLD)$(GREEN)Running all tests...$(RESET)"
	$(SWIFT) test
	@echo "$(GREEN)✓ All tests passed$(RESET)"

## test-unit: Run unit tests only (skip integration tests)
test-unit:
	@echo "$(BOLD)$(GREEN)Running unit tests...$(RESET)"
	$(SWIFT) test --filter "test" --skip "testDownloadRealAppleDocPage"
	@echo "$(GREEN)✓ Unit tests passed$(RESET)"

## test-integration: Run integration tests only
test-integration:
	@echo "$(BOLD)$(GREEN)Running integration tests...$(RESET)"
	$(SWIFT) test --filter "testDownloadRealAppleDocPage"
	@echo "$(GREEN)✓ Integration tests passed$(RESET)"

## clean: Clean build artifacts
clean:
	@echo "$(BOLD)$(YELLOW)Cleaning build artifacts...$(RESET)"
	$(SWIFT) package clean
	rm -rf $(BUILD_DIR)
	@echo "$(GREEN)✓ Clean complete$(RESET)"

## distclean: Clean everything including Package.resolved
distclean: clean
	@echo "$(BOLD)$(YELLOW)Removing Package.resolved...$(RESET)"
	rm -f Package.resolved
	@echo "$(GREEN)✓ Distclean complete$(RESET)"

## format: Format Swift code (requires swift-format)
format:
	@if command -v swift-format >/dev/null 2>&1; then \
		echo "$(BOLD)$(GREEN)Formatting Swift code...$(RESET)"; \
		find Sources Tests -name "*.swift" -exec swift-format -i {} \;; \
		echo "$(GREEN)✓ Format complete$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ swift-format not found. Install: brew install swift-format$(RESET)"; \
		exit 1; \
	fi

## lint: Lint Swift code (requires SwiftLint)
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		echo "$(BOLD)$(GREEN)Linting Swift code...$(RESET)"; \
		swiftlint; \
		echo "$(GREEN)✓ Lint complete$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ SwiftLint not found. Install: brew install swiftlint$(RESET)"; \
		exit 1; \
	fi

## archive: Create release archive
archive: build-release
	@echo "$(BOLD)$(GREEN)Creating release archive...$(RESET)"
	@VERSION=$$($(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) --version); \
	ARCHIVE_NAME="docsucker-$$VERSION-$(ARCH)-apple-darwin"; \
	mkdir -p "$$ARCHIVE_NAME/bin"; \
	cp $(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) "$$ARCHIVE_NAME/bin/"; \
	cp $(BUILD_DIR)/release/$(PRODUCT_NAME_MCP) "$$ARCHIVE_NAME/bin/"; \
	cp README.md "$$ARCHIVE_NAME/"; \
	cp DOCSUCKER_CLI_README.md "$$ARCHIVE_NAME/"; \
	cp MCP_SERVER_README.md "$$ARCHIVE_NAME/"; \
	tar -czf "$$ARCHIVE_NAME.tar.gz" "$$ARCHIVE_NAME"; \
	rm -rf "$$ARCHIVE_NAME"; \
	echo "$(GREEN)✓ Archive created: $$ARCHIVE_NAME.tar.gz$(RESET)"

## bottle: Create Homebrew bottle
bottle: build-release
	@echo "$(BOLD)$(GREEN)Creating Homebrew bottle...$(RESET)"
	@VERSION=$$($(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) --version); \
	BOTTLE_NAME="docsucker-$$VERSION.$(ARCH)_monterey.bottle.tar.gz"; \
	mkdir -p bottle/$(PREFIX)/bin; \
	cp $(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) bottle/$(PREFIX)/bin/; \
	cp $(BUILD_DIR)/release/$(PRODUCT_NAME_MCP) bottle/$(PREFIX)/bin/; \
	cd bottle && tar -czf "../$$BOTTLE_NAME" .; \
	rm -rf bottle; \
	echo "$(GREEN)✓ Bottle created: $$BOTTLE_NAME$(RESET)"; \
	shasum -a 256 "$$BOTTLE_NAME"

# Development helpers
.PHONY: dev run-cli run-mcp watch

## dev: Quick development build
dev:
	@$(SWIFT) build

## run-cli: Run CLI in debug mode (pass args with ARGS="...")
run-cli: build-debug
	@echo "$(BOLD)$(GREEN)Running $(PRODUCT_NAME_CLI)...$(RESET)"
	$(BUILD_DIR)/debug/$(PRODUCT_NAME_CLI) $(ARGS)

## run-mcp: Run MCP server in debug mode
run-mcp: build-debug
	@echo "$(BOLD)$(GREEN)Running $(PRODUCT_NAME_MCP)...$(RESET)"
	$(BUILD_DIR)/debug/$(PRODUCT_NAME_MCP) serve $(ARGS)

## watch: Watch for changes and rebuild (requires fswatch)
watch:
	@if command -v fswatch >/dev/null 2>&1; then \
		echo "$(BOLD)$(GREEN)Watching for changes...$(RESET)"; \
		fswatch -o Sources Tests | xargs -n1 -I{} make build-debug; \
	else \
		echo "$(YELLOW)⚠ fswatch not found. Install: brew install fswatch$(RESET)"; \
		exit 1; \
	fi

# Version information
.PHONY: version

## version: Show version information
version:
	@echo "$(BOLD)Docsucker Version Information$(RESET)"
	@if [ -f $(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) ]; then \
		echo "  CLI: $$($(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) --version)"; \
		echo "  MCP: $$($(BUILD_DIR)/release/$(PRODUCT_NAME_MCP) --version)"; \
	elif [ -f $(BUILD_DIR)/debug/$(PRODUCT_NAME_CLI) ]; then \
		echo "  CLI: $$($(BUILD_DIR)/debug/$(PRODUCT_NAME_CLI) --version)"; \
		echo "  MCP: $$($(BUILD_DIR)/debug/$(PRODUCT_NAME_MCP) --version)"; \
	else \
		echo "  $(YELLOW)Not built yet. Run: make build$(RESET)"; \
	fi
	@echo "  Swift: $$($(SWIFT) --version | head -1)"
	@echo "  Architecture: $(ARCH)"

# Shortcuts
.PHONY: b i u t c

b: build
i: install
u: uninstall
t: test
c: clean
