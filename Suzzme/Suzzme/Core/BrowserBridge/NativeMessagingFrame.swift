#if os(macOS)
import Foundation
import Darwin

/// Chrome's STDIO framing is bounded before allocation. A silent/malicious peer
/// cannot keep a host process indefinitely waiting for its length or payload.
enum NativeFrame {
    static func read(fd: Int32, deadline: Date) throws -> Data {
        func exact(_ count: Int) throws -> Data {
            var bytes = [UInt8](repeating: 0, count: count), offset = 0
            while offset < count {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { throw BridgeFailure.unavailable }
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&descriptor, 1, Int32(min(remaining * 1000, 5000)))
                if ready < 0 && errno == EINTR { continue }
                guard ready > 0 else { throw BridgeFailure.unavailable }
                let result = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress?.advanced(by: offset), count - offset) }
                if result < 0 && errno == EINTR { continue }
                guard result > 0 else { throw BridgeFailure.invalid }
                offset += result
            }
            return Data(bytes)
        }
        let header = try exact(4)
        let size = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard size > 0, size <= BrowserBridgeEngine.maximumFrame else { throw BridgeFailure.invalid }
        return try exact(Int(size))
    }
    static func write(_ data: Data, fd: Int32) throws {
        guard !data.isEmpty, data.count <= BrowserBridgeEngine.maximumFrame else { throw BridgeFailure.invalid }
        var length = UInt32(data.count)
        var framed = withUnsafeBytes(of: &length) { Data($0) }; framed.append(data)
        var offset = 0
        while offset < framed.count {
            let count = framed.withUnsafeBytes { Darwin.write(fd, $0.baseAddress?.advanced(by: offset), framed.count - offset) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw BridgeFailure.unavailable }
            offset += count
        }
    }
}
#endif
