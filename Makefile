.PHONY: build test lint purity ci ai-test

build:
	xcodebuild build -project Wharfside.xcodeproj -scheme Wharfside \
	  -destination 'platform=macOS,arch=arm64' | xcbeautify

test:
	xcodebuild test -project Wharfside.xcodeproj -scheme Wharfside \
	  -destination 'platform=macOS,arch=arm64' \
	  -skip-testing:WharfsideUITests | xcbeautify
	cd Packages/WharfsideAnalysis && swift test -Xswiftc -warnings-as-errors

lint:
	swiftlint --strict

purity:
	@! grep -rnE '^\s*import (SwiftUI|FoundationModels|AppKit)' \
	  Packages/WharfsideAnalysis/Sources/ \
	  || (echo "WharfsideAnalysis must stay pure (AI_INTEGRATION.md §2)"; exit 1)

ci: lint purity build test

ai-test:
	mkdir -p .artifacts && touch .artifacts/.run-ai-regression
	xcodebuild test -project Wharfside.xcodeproj -scheme Wharfside \
	  -destination 'platform=macOS,arch=arm64' \
	  -only-testing:WharfsideTests/DiagnosisRegressionTests \
	  -parallel-testing-enabled NO | xcbeautify