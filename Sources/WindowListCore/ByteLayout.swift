extension InlineArray where Element == UInt8 {
    /// Stores `value` little-endian at `offset`. Traps (never writes out of bounds) if it doesn't fit.
    mutating func storeLittleEndian<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        let size = MemoryLayout<T>.size
        precondition(offset >= 0 && offset + size <= count, "store of \(size) bytes at \(offset) exceeds \(count)")
        let bits = value.littleEndian
        (0..<size).forEach { index in
            self[offset + index] = UInt8(truncatingIfNeeded: bits >> (index * 8))
        }
    }

    /// Loads a little-endian `T` from `offset`. Traps (never reads out of bounds) if it doesn't fit.
    public func loadLittleEndian<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        let size = MemoryLayout<T>.size
        precondition(offset >= 0 && offset + size <= count, "load of \(size) bytes at \(offset) exceeds \(count)")
        return (0..<size).reduce(T.zero) { partial, index in
            partial | (T(truncatingIfNeeded: self[offset + index]) << (index * 8))
        }
    }
}
