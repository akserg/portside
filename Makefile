.PHONY: build test lint purity ci ai-test sign-rulebook verify-rulebook snapshot-assets demo-env

# Propagate failures from pipelines (xcodebuild | xcbeautify).
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

RULEBOOK_JSON_APP := Wharfside/Resources/Rulebook.json
RULEBOOK_SIG_APP := Wharfside/Resources/Rulebook.json.sig
RULEBOOK_JSON_PKG := Packages/RulebookCore/Sources/RulebookCore/Resources/Rulebook.json
RULEBOOK_SIG_PKG := Packages/RulebookCore/Sources/RulebookCore/Resources/Rulebook.json.sig
RULEBOOK_KEY ?= $(RULEBOOK_SIGNING_KEY)

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
	  Packages/RulebookCore/Sources/ \
	  || (echo "WharfsideAnalysis and RulebookCore must stay pure (AI_INTEGRATION.md §2)"; exit 1)
	# Nested NavigationSplitViews do not negotiate column mins (resize half-hide). Exactly one.
	@count=$$(grep -rEn 'NavigationSplitView[[:space:]]*[({]' Wharfside --include='*.swift' \
	  | wc -l | tr -d ' '); \
	  if [ "$$count" -ne 1 ]; then \
	    echo "expected exactly one NavigationSplitView in Wharfside/ (found $$count)"; \
	    grep -rEn 'NavigationSplitView[[:space:]]*[({]' Wharfside --include='*.swift' || true; \
	    exit 1; \
	  fi

verify-rulebook:
	cd Packages/RulebookCore && swift run -c release rulebook-tool verify \
	  --document ../../$(RULEBOOK_JSON_APP) --sig ../../$(RULEBOOK_SIG_APP)
	cd Packages/RulebookCore && swift run -c release rulebook-tool verify \
	  --document Sources/RulebookCore/Resources/Rulebook.json \
	  --sig Sources/RulebookCore/Resources/Rulebook.json.sig
	@diff -q $(RULEBOOK_JSON_APP) $(RULEBOOK_JSON_PKG)
	@diff -q $(RULEBOOK_SIG_APP) $(RULEBOOK_SIG_PKG)

sign-rulebook:
	@test -n "$(RULEBOOK_KEY)" || (echo "Set RULEBOOK_SIGNING_KEY to absolute path of private key .b64"; exit 1)
	cd Packages/RulebookCore && swift run -c release rulebook-tool sign \
	  --key "$(RULEBOOK_KEY)" \
	  --document Sources/RulebookCore/Resources/Rulebook.json \
	  --out Sources/RulebookCore/Resources/Rulebook.json.sig
	cp $(RULEBOOK_SIG_PKG) $(RULEBOOK_SIG_APP)
	@$(MAKE) verify-rulebook

ci: lint purity verify-rulebook build test rulebook-linux

rulebook-test:
	cd Packages/RulebookCore && swift test -Xswiftc -warnings-as-errors

# Ground-truth Linux purity check for RulebookCore (B3 acceptance criterion).
# Requires apple/container or Docker. CI runs the same step in rulebook-core-linux.
rulebook-linux:
	container run --rm \
	  -v "$(PWD)/Packages/RulebookCore:/src" \
	  -w /src \
	  swift:6.0 \
	  swift test -c release -Xswiftc -warnings-as-errors

ai-test:
	mkdir -p .artifacts && touch .artifacts/.run-ai-regression
	xcodebuild test -project Wharfside.xcodeproj -scheme Wharfside \
	  -destination 'platform=macOS,arch=arm64' \
	  -only-testing:WharfsideTests/DiagnosisRegressionTests \
	  -parallel-testing-enabled NO | xcbeautify

# B5 bonus — Debug snapshot smoke (ImageRenderer PNGs; no daemon).
snapshot-assets:
	./scripts/capture-assets.sh .artifacts/launch-assets

# Curated hello/crashy/web cast for live MainView marketing captures.
demo-env:
	./scripts/setup-demo-env.sh --purge
