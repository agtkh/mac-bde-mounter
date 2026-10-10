// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// A byte buffer for secrets that is zeroed with `memset_s` when it is
/// cleared or deallocated (requirement 4.1: memory protection).
public final class SecureBytes {
    public private(set) var bytes: [UInt8]

    public init(_ bytes: [UInt8]) { self.bytes = bytes }

    public convenience init(data: Data) { self.init([UInt8](data)) }

    /// Converts a String to bytes. The String itself cannot be wiped reliably
    /// by Swift, so callers should drop their references as soon as possible.
    public convenience init(string: String) { self.init(Array(string.utf8)) }

    public var count: Int { bytes.count }
    public var isEmpty: Bool { bytes.isEmpty }

    /// Copies into a `Data` for XPC transport. The returned Data is wiped by
    /// `SecureBytes.wipe(_:)` once the message has been sent.
    public func makeData() -> Data { Data(bytes) }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    public func clear() {
        let n = bytes.count
        guard n > 0 else { return }
        bytes.withUnsafeMutableBytes { ptr in
            _ = memset_s(ptr.baseAddress, n, 0, n)
        }
        bytes.removeAll(keepingCapacity: false)
    }

    deinit { clear() }

    public static func wipe(_ data: inout Data) {
        let n = data.count
        guard n > 0 else { return }
        data.withUnsafeMutableBytes { ptr in
            _ = memset_s(ptr.baseAddress, n, 0, n)
        }
        data.removeAll(keepingCapacity: false)
    }
}
