import CursorBarDomain
import XCTest

final class ModelDisplayNamesFamilyTests: XCTestCase {
    func testClassifiesCatalogIdsTheWayNewtonDoes() {
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "default", displayName: "Auto"), .auto)
        XCTAssertEqual(
            ModelDisplayNames.Family.of(modelIntent: "grok-4.6", displayName: "Cursor Grok 4.6"),
            .grok
        )
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "composer-2.5"), .composer)
        XCTAssertEqual(
            ModelDisplayNames.Family.of(modelIntent: "opus-5", displayName: "Claude Opus 5"),
            .claude
        )
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "gpt-5.6-sol"), .gpt)
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "gemini-3.5-flash"), .gemini)
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "kimi-k2.7-code"), .kimi)
        XCTAssertEqual(
            ModelDisplayNames.Family.of(modelIntent: "glm-4.5", displayName: "GLM 4.5"),
            .glm
        )
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "mystery-9"), .other)
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "cursor-small"), .other)
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "o3"), .other)
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "codex-5.3"), .gpt)
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "sonnet-5"), .claude)
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "fable-5"), .claude)
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "cursor-grok-4.5-high"), .grok)
        XCTAssertEqual(ModelDisplayNames.Family.of(modelIntent: "grok-4.5-xhigh"), .grok)
    }

    func testFamilySymbolsAreDistinct() {
        let symbols = ModelDisplayNames.Family.allCases.map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, symbols.count)
        XCTAssertEqual(ModelDisplayNames.Family.grok.symbolName, "cube.fill")
    }

    func testFamilyTitlesMatchNewtonLabels() {
        XCTAssertEqual(
            ModelDisplayNames.Family.allCases.map(\.title),
            [
                "Auto",
                "Cursor Grok",
                "Composer",
                "Claude",
                "GPT",
                "Gemini",
                "Kimi",
                "GLM",
                "Other",
            ]
        )
    }

    func testLineSplitsGenerationTheWayNewtonDoes() {
        XCTAssertEqual(
            ModelDisplayNames.Line.of(
                family: .grok,
                modelIntent: "cursor-grok-4.5-high-fast",
                displayName: "Cursor Grok 4.5 High Fast"
            ).title,
            "Cursor Grok 4.5"
        )
        XCTAssertEqual(
            ModelDisplayNames.Line.of(
                family: .grok,
                modelIntent: "cursor-grok-4.6-xhigh-fast",
                displayName: "Cursor Grok 4.6 XHigh Fast"
            ).title,
            "Cursor Grok 4.6"
        )
        XCTAssertEqual(
            ModelDisplayNames.Line.of(
                family: .composer,
                modelIntent: "composer-2.5-fast",
                displayName: "Composer 2.5 Fast"
            ).title,
            "Composer 2.5"
        )
        XCTAssertEqual(
            ModelDisplayNames.Line.of(
                family: .composer,
                modelIntent: "composer-2",
                displayName: "Composer 2"
            ).title,
            "Composer 2"
        )
        XCTAssertEqual(
            ModelDisplayNames.Line.of(
                family: .claude,
                modelIntent: "claude-4.6-sonnet-medium-thinking",
                displayName: "Claude 4.6 Sonnet Medium Thinking"
            ).title,
            "Sonnet 4.6"
        )
        XCTAssertEqual(
            ModelDisplayNames.Line.of(
                family: .claude,
                modelIntent: "opus-5",
                displayName: "Claude Opus 5"
            ).title,
            "Opus 5"
        )
        XCTAssertEqual(
            ModelDisplayNames.Line.of(
                family: .gpt,
                modelIntent: "gpt-5.6-sol-medium",
                displayName: "GPT 5.6 Sol Medium"
            ).title,
            "GPT 5.6"
        )
        XCTAssertEqual(
            ModelDisplayNames.Line.of(
                family: .gemini,
                modelIntent: "gemini-3.5-flash",
                displayName: "Gemini 3.5 Flash"
            ).title,
            "Gemini 3.5"
        )
    }

    func testGrokDisplayNamesUseCursorGrokPrefix() {
        XCTAssertEqual(
            ModelDisplayNames.displayName(for: "cursor-grok-4.5-high-fast"),
            "Cursor Grok 4.5 High Fast"
        )
        XCTAssertEqual(
            ModelDisplayNames.displayName(for: "grok-4.5-xhigh"),
            "Cursor Grok 4.5 XHigh"
        )
        XCTAssertEqual(ModelDisplayNames.displayName(for: "default"), "Auto")
    }

    func testPlacementKeepsVariantOffTheLine() {
        let placement = ModelPlacement.of(
            modelIntent: "cursor-grok-4.5-high-fast",
            displayName: "Cursor Grok 4.5 High Fast"
        )
        XCTAssertEqual(placement.family, .grok)
        XCTAssertEqual(placement.line.title, "Cursor Grok 4.5")
        XCTAssertEqual(placement.variant, "High Fast")
        let other = ModelPlacement.of(modelIntent: "alpha", displayName: "Alpha")
        XCTAssertEqual(other.family, .other)
        XCTAssertEqual(other.line.title, "Alpha")
        XCTAssertNil(other.variant)
    }
}
