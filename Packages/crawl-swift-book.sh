#!/bin/bash
# Crawl Swift.org documentation (The Swift Programming Language book)
# This will be built into v0.1.3 but won't affect the running v0.1.2 crawl

BASE_DIR="/Volumes/Code/DeveloperExt/appledocsucker"
DOCS_DIR="$BASE_DIR/swift-book"
LOG_FILE="$BASE_DIR/swift-book-crawl.log"

echo "🚀 Swift.org Documentation Crawl (v0.1.3)"
echo "   Start URL: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/"
echo "   Output: $DOCS_DIR"
echo "   Log: $LOG_FILE"
echo "   Max pages: 200 (estimated ~60-80 pages)"
echo "   Max depth: 10"
echo ""
echo "⚠️  NOTE: This requires building v0.1.3 first!"
echo "   The current running crawl (v0.1.2) will NOT be affected."
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Build v0.1.3 (this will update the symlink)
echo ""
echo "🔨 Building v0.1.3..."
cd "$(dirname "$0")"
swift build -c release

# Run the Swift.org crawl
echo ""
echo "📚 Starting Swift.org crawl..."
.build/release/appledocsucker crawl \
  --start-url "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/" \
  --output-dir "$DOCS_DIR" \
  --max-pages 200 \
  --max-depth 10 \
  --resume 2>&1 | tee -a "$LOG_FILE"
