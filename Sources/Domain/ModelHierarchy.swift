import Foundation

/// One slug’s place in the Newton tree: family → generation → leftover variant.
public struct ModelPlacement: Sendable, Equatable, Hashable {
    public let family: ModelDisplayNames.Family
    public let line: ModelDisplayNames.Line
    public let variant: String?

    public init(family: ModelDisplayNames.Family, line: ModelDisplayNames.Line, variant: String?) {
        self.family = family
        self.line = line
        self.variant = variant
    }

    public static func of(modelIntent: String, displayName: String? = nil) -> ModelPlacement {
        let name = displayName ?? ModelDisplayNames.displayName(for: modelIntent)
        let family = ModelDisplayNames.Family.of(modelIntent: modelIntent, displayName: name)
        let line = ModelDisplayNames.Line.of(
            family: family,
            modelIntent: modelIntent,
            displayName: name
        )
        return ModelPlacement(family: family, line: line, variant: variantName(displayName: name, line: line))
    }

    private static func variantName(displayName: String, line: ModelDisplayNames.Line) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(line.title.lowercased()) else { return nil }
        let rest = trimmed.dropFirst(line.title.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}

public struct ModelLineGroup<Item: Sendable>: Sendable {
    public let family: ModelDisplayNames.Family
    public let line: ModelDisplayNames.Line
    public let items: [Item]

    public init(family: ModelDisplayNames.Family, line: ModelDisplayNames.Line, items: [Item]) {
        self.family = family
        self.line = line
        self.items = items
    }
}

public struct ModelFamilyGroup<Item: Sendable>: Sendable {
    public let family: ModelDisplayNames.Family
    public let lines: [ModelLineGroup<Item>]

    public init(family: ModelDisplayNames.Family, lines: [ModelLineGroup<Item>]) {
        self.family = family
        self.lines = lines
    }

    public var items: [Item] { lines.flatMap(\.items) }

    /// Generation headers only when this family actually splits (Grok 4.6 vs 4.5).
    public var showsLineHeaders: Bool {
        lines.count > 1 && lines.contains { $0.line.hasVersion }
    }
}

/// One grouping path for catalog rows and Usage top-models.
public enum ModelHierarchy {
    public static func grouped<Item: Sendable>(
        _ items: [Item],
        intent: KeyPath<Item, String>,
        displayName: KeyPath<Item, String>
    ) -> [ModelFamilyGroup<Item>] {
        var lineBuckets: [ModelDisplayNames.Family: [ModelDisplayNames.Line: [Item]]] = [:]
        for item in items {
            let placement = ModelPlacement.of(
                modelIntent: item[keyPath: intent],
                displayName: item[keyPath: displayName]
            )
            lineBuckets[placement.family, default: [:]][placement.line, default: []].append(item)
        }
        return ModelDisplayNames.Family.allCases.compactMap { family in
            guard let lines = lineBuckets[family], !lines.isEmpty else { return nil }
            let ordered = lines.keys.sorted(by: ModelDisplayNames.Line.sortNewestFirst).compactMap { line -> ModelLineGroup<Item>? in
                guard let members = lines[line], !members.isEmpty else { return nil }
                return ModelLineGroup(family: family, line: line, items: members)
            }
            guard !ordered.isEmpty else { return nil }
            return ModelFamilyGroup(family: family, lines: ordered)
        }
    }
}
