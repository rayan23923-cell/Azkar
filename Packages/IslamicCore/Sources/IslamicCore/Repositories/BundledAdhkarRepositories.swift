import Foundation

/// Reads `Content/adhkar.json`.
public actor BundledDhikrRepository: DhikrRepository {
    private let source: BundledContentSource
    private var cache: [GroupFile<DhikrItem>]?

    public init(source: BundledContentSource = .bundled) {
        self.source = source
    }

    public func loadGroups() async throws -> [DhikrGroup] {
        try content().map { DhikrGroup(id: DhikrGroup.ID(rawValue: $0.id), titleArabic: $0.titleArabic) }
    }

    public func loadItems(group: DhikrGroup.ID) async throws -> [DhikrItem] {
        guard let entry = try content().first(where: { $0.id == group.rawValue }) else {
            throw ContentError.notFound("dhikr group \(group.rawValue)")
        }
        return entry.items
    }

    public func loadItem(id: String) async throws -> DhikrItem {
        guard let item = try content().lazy.flatMap(\.items).first(where: { $0.id == id }) else {
            throw ContentError.notFound("dhikr \(id)")
        }
        return item
    }

    private func content() throws -> [GroupFile<DhikrItem>] {
        if let cache { return cache }
        let groups = try source.decode(AdhkarFile.self, resource: "adhkar").groups
        try validate(groups, kind: "adhkar", owner: { $0.group.rawValue })
        for item in groups.flatMap(\.items) {
            try requireContent(item.repeatCount >= 1, "adhkar: \(item.id) repeatCount")
        }
        cache = groups
        return groups
    }
}

/// Reads `Content/duas.json`.
public actor BundledDuaRepository: DuaRepository {
    private let source: BundledContentSource
    private var cache: [GroupFile<DuaItem>]?

    public init(source: BundledContentSource = .bundled) {
        self.source = source
    }

    public func loadCategories() async throws -> [DuaCategory] {
        try content().map { DuaCategory(id: DuaCategory.ID(rawValue: $0.id), titleArabic: $0.titleArabic) }
    }

    public func loadItems(category: DuaCategory.ID) async throws -> [DuaItem] {
        guard let entry = try content().first(where: { $0.id == category.rawValue }) else {
            throw ContentError.notFound("dua category \(category.rawValue)")
        }
        return entry.items
    }

    public func loadItem(id: String) async throws -> DuaItem {
        guard let item = try content().lazy.flatMap(\.items).first(where: { $0.id == id }) else {
            throw ContentError.notFound("dua \(id)")
        }
        return item
    }

    private func content() throws -> [GroupFile<DuaItem>] {
        if let cache { return cache }
        let categories = try source.decode(DuasFile.self, resource: "duas").categories
        try validate(categories, kind: "duas", owner: { $0.category.rawValue })
        cache = categories
        return categories
    }
}

struct GroupFile<Item: Decodable>: Decodable {
    let id: String
    let titleArabic: String
    let items: [Item]
}

private struct AdhkarFile: Decodable {
    let groups: [GroupFile<DhikrItem>]
}

private struct DuasFile: Decodable {
    let categories: [GroupFile<DuaItem>]
}

private protocol OrderedContent {
    var id: String { get }
    var order: Int { get }
    var arabicText: String { get }
    var source: String { get }
}

extension DhikrItem: OrderedContent {}
extension DuaItem: OrderedContent {}

private func validate<Item: OrderedContent>(_ groups: [GroupFile<Item>], kind: String,
                                            owner: (Item) -> String) throws {
    try requireContent(!groups.isEmpty, "\(kind): no groups")
    try requireContent(Set(groups.map(\.id)).count == groups.count, "\(kind): duplicate group ids")
    var ids = Set<String>()
    for group in groups {
        try requireContent(!group.items.isEmpty, "\(kind): \(group.id) is empty")
        for (offset, item) in group.items.enumerated() {
            try requireContent(owner(item) == group.id, "\(kind): \(item.id) is in the wrong group")
            try requireContent(item.order == offset + 1, "\(kind): \(item.id) order")
            try requireContent(!item.arabicText.isEmpty && !item.source.isEmpty, "\(kind): \(item.id) empty text or source")
            try requireContent(ids.insert(item.id).inserted, "\(kind): duplicate id \(item.id)")
        }
    }
}
