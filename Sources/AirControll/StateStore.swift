import Darwin
import Foundation

final class StateStore: @unchecked Sendable {
  static let shared = StateStore()

  let applicationSupportURL: URL
  let stateURL: URL

  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let fileManager = FileManager.default
  private let ioQueue = DispatchQueue(label: "com.aircontroll.state-store", qos: .utility)

  private init() {
    let base = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!

    applicationSupportURL = base.appendingPathComponent(
      "AirControll",
      isDirectory: true
    )
    stateURL = applicationSupportURL.appendingPathComponent(
      "gesture-state.json"
    )

    encoder = JSONEncoder()
    encoder.outputFormatting = [
      .prettyPrinted,
      .sortedKeys,
      .withoutEscapingSlashes,
    ]
    encoder.dateEncodingStrategy = .iso8601

    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  func load() -> AppConfiguration {
    do {
      try fileManager.createDirectory(
        at: applicationSupportURL,
        withIntermediateDirectories: true
      )
    } catch {
      return normalizedDefaults()
    }

    guard fileManager.fileExists(atPath: stateURL.path) else {
      return normalizedDefaults()
    }

    do {
      var configuration = try decode(at: stateURL)
      configuration.normalize()
      return configuration
    } catch {
      // No backup, quarantine or automatic recovery is performed.
      // Defaults remain in memory until the user changes a setting,
      // at which point the unreadable file is replaced atomically.
      return normalizedDefaults()
    }
  }

  func save(
    _ configuration: AppConfiguration,
    completion: (@MainActor @Sendable (Result<Void, Error>) -> Void)? = nil
  ) {
    var normalized = configuration
    normalized.normalize()
    let snapshot = normalized

    ioQueue.async { [self] in
      let result = Result { try saveSynchronously(snapshot) }
      if let completion {
        Task { @MainActor in
          completion(result)
        }
      }
    }
  }

  func saveImmediately(_ configuration: AppConfiguration) throws {
    var normalized = configuration
    normalized.normalize()
    try ioQueue.sync {
      try saveSynchronously(normalized)
    }
  }

  func deleteLearnedData() throws -> AppConfiguration {
    try ioQueue.sync {
      if fileManager.fileExists(atPath: stateURL.path) {
        try fileManager.removeItem(at: stateURL)
      }

      let defaults = normalizedDefaults()
      try saveSynchronously(defaults)
      return defaults
    }
  }

  private func normalizedDefaults() -> AppConfiguration {
    var defaults = AppConfiguration.defaults()
    defaults.normalize()
    return defaults
  }

  private func decode(at url: URL) throws -> AppConfiguration {
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    let configuration = try decoder.decode(
      AppConfiguration.self,
      from: data
    )

    guard configuration.schemaVersion
      <= AppConfiguration.currentSchemaVersion
    else {
      throw StateStoreError.unsupportedSchemaVersion(
        configuration.schemaVersion
      )
    }

    return configuration
  }

  private func saveSynchronously(
    _ configuration: AppConfiguration
  ) throws {
    try fileManager.createDirectory(
      at: applicationSupportURL,
      withIntermediateDirectories: true
    )

    let data = try encoder.encode(configuration)
    let temporaryURL = applicationSupportURL.appendingPathComponent(
      "gesture-state.tmp-\(UUID().uuidString)"
    )

    defer {
      try? fileManager.removeItem(at: temporaryURL)
    }

    try data.write(to: temporaryURL, options: [.atomic])

    if fileManager.fileExists(atPath: stateURL.path) {
      try atomicReplaceItem(
        at: stateURL,
        with: temporaryURL
      )
    } else {
      try fileManager.moveItem(
        at: temporaryURL,
        to: stateURL
      )
    }
  }

  private func atomicReplaceItem(
    at destinationURL: URL,
    with sourceURL: URL
  ) throws {
    let result: Int32 = sourceURL.withUnsafeFileSystemRepresentation {
      sourcePath in
      destinationURL.withUnsafeFileSystemRepresentation {
        destinationPath in
        guard let sourcePath, let destinationPath else {
          return Int32(-1)
        }
        return rename(sourcePath, destinationPath)
      }
    }

    guard result == 0 else {
      throw NSError(
        domain: NSPOSIXErrorDomain,
        code: Int(errno),
        userInfo: [
          NSFilePathErrorKey: destinationURL.path,
          NSUnderlyingErrorKey: POSIXError(
            POSIXErrorCode(rawValue: errno) ?? .EIO
          ),
        ]
      )
    }
  }
}

enum StateStoreError: LocalizedError {
  case unsupportedSchemaVersion(Int)

  var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      "The saved configuration uses unsupported schema version \(version)."
    }
  }
}
