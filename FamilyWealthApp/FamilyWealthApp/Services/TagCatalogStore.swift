import Foundation

enum TagCatalogKind {
    case category
    case platform

    fileprivate var storageKey: String {
        switch self {
        case .category:
            return "tag-catalog-category-v1"
        case .platform:
            return "tag-catalog-platform-v1"
        }
    }
}

enum TagCatalogStore {
    static func tags(for kind: TagCatalogKind) -> [String] {
        let rawValues = UserDefaults.standard.array(forKey: kind.storageKey) as? [String] ?? []
        return normalize(rawValues)
    }

    static func add(_ value: String, kind: TagCatalogKind) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return
        }

        var all = tags(for: kind)
        if !contains(clean, in: all) {
            all.append(clean)
        }
        persist(all, for: kind)
    }

    static func remove(_ value: String, kind: TagCatalogKind) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return
        }

        let filtered = tags(for: kind).filter {
            $0.caseInsensitiveCompare(clean) != .orderedSame
        }
        persist(filtered, for: kind)
    }

    static func rename(oldValue: String, newValue: String, kind: TagCatalogKind) {
        let oldClean = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newClean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldClean.isEmpty, !newClean.isEmpty else {
            return
        }

        var all = tags(for: kind)
        if let index = all.firstIndex(where: { $0.caseInsensitiveCompare(oldClean) == .orderedSame }) {
            all[index] = newClean
        } else if !contains(newClean, in: all) {
            all.append(newClean)
        }
        persist(all, for: kind)
    }

    private static func persist(_ values: [String], for kind: TagCatalogKind) {
        UserDefaults.standard.set(normalize(values), forKey: kind.storageKey)
    }

    private static func normalize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for raw in values {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                continue
            }

            let lower = clean.lowercased()
            guard !seen.contains(lower) else {
                continue
            }
            seen.insert(lower)
            output.append(clean)
        }

        return output.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private static func contains(_ value: String, in values: [String]) -> Bool {
        values.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}
