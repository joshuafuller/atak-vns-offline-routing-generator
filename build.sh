#!/bin/bash
# Build script for VNS Interactive v2.0

set -e

echo "🔨 Building ATAK VNS Interactive v2.0..."
echo "======================================="

cd go-src

echo "📦 Downloading dependencies..."
go mod tidy

echo "🐧 Building Linux binary..."
go build -o ../vns-interactive .

echo "🪟 Building Windows binary..."
GOOS=windows GOARCH=amd64 go build -o ../vns-interactive.exe .

echo "🍎 Building macOS Intel binary..."
GOOS=darwin GOARCH=amd64 go build -o ../vns-interactive-darwin-intel .

echo "🍎 Building macOS Apple Silicon binary..."
GOOS=darwin GOARCH=arm64 go build -o ../vns-interactive-darwin-arm64 .

cd ..

echo "✅ Build complete!"
echo ""
echo "📁 Generated binaries:"
echo "   🐧 Linux:              ./vns-interactive"
echo "   🪟 Windows:            ./vns-interactive.exe"
echo "   🍎 macOS (Intel):      ./vns-interactive-darwin-intel"
echo "   🍎 macOS (ARM):        ./vns-interactive-darwin-arm64"
echo ""
echo "🚀 Test with: ./vns-interactive --help"