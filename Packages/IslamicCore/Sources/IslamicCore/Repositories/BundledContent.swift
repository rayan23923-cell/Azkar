import Foundation

/// Where bundled JSON comes from. Tests pass raw data to exercise invalid content.
public enum BundledContentSource: Sendable {
    case bundled
    case data(Data)

    static let supportedFormatVersion = 1

    func load(_ resource: String) throws -> Data {
        switch self {
        case .data(let data):
            return data
        case .bundled:
            guard let url = Bundle.module.url(forResource: resource, withExtension: "json", subdirectory: "Content") else {
                throw ContentError.resourceMissing("\(resource).json")
            }
            return try Data(contentsOf: url)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, resource: String) throws -> T {
        let data = try load(resource)
        let header: FormatHeader
        do {
            header = try JSONDecoder().decode(FormatHeader.self, from: data)
        } catch {
            throw ContentError.invalidContent("\(resource): \(error)")
        }
        guard header.formatVersion == Self.supportedFormatVersion else {
            throw ContentError.unsupportedFormatVersion(header.formatVersion)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ContentError.invalidContent("\(resource): \(error)")
        }
    }
}

private struct FormatHeader: Decodable {
    let formatVersion: Int
}

func requireContent(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw ContentError.invalidContent(message()) }
}
