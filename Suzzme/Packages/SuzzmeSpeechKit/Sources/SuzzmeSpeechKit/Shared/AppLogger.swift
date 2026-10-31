// Adapted from FluidAudio v0.15.2. Logging deliberately disabled in Suzzme
// to keep response text out of Debug console and Unified Logging.
public struct AppLogger: Sendable {
 public init(category: String) {}
 public init(subsystem: String, category: String) {}
 public func debug(_ message: String) {}
 public func info(_ message: String) {}
 public func notice(_ message: String) {}
 public func warning(_ message: String) {}
 public func error(_ message: String) {}
 public func fault(_ message: String) {}
}
