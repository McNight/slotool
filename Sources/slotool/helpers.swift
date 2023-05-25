import Foundation
import MachO
import Algorithms

extension FileHandle {
    func parse<T>(_ type: T.Type, swap: Bool = false) throws -> T {
        let count = MemoryLayout<T>.size
        guard let data = try read(upToCount: count) else {
            throw RuntimeError("Got nil data when trying to read \(count) bytes.")
        }
        let inOrderData = swap ? data.swapEndian : data
        return inOrderData.withUnsafeBytes { $0.load(as: type) }
    }
}

extension Data {
    /// Is there another way ? There probably is...
    var swapEndian: Data {
        var data = Data(capacity: count)
        chunks(ofCount: 4).forEach { data.append(contentsOf: $0.reversed()) }
        return data
    }
}

private func int8TupleToString(_ subject: Any, swap: Bool) -> String {
    let chars: some Collection<Int8> = Mirror(reflecting: subject)
        .children
        .compactMap { $0.value as? Int8 }
    if swap {
        let swapped = chars
            .chunks(ofCount: 4)
            .map { $0.reversed() }
            .flatMap { $0 }
            .map { Character(UnicodeScalar(UInt8($0))) }
        return String(swapped)
    } else {
        return String(chars.map { Character(UnicodeScalar(UInt8($0))) })
    }
}

private func uint8TupleToHexString(_ subject: Any, swap: Bool) -> String {
    let hexChars: some Collection<UInt8> = Mirror(reflecting: subject)
        .children
        .compactMap { $0.value as? UInt8 }
    if swap {
        return hexChars
            .chunks(ofCount: 4)
            .map { $0.reversed() }
            .flatMap { $0 }
            .map { String(format: "%02X", $0) }
            .joined()
    } else {
        return hexChars
            .map { String(format: "%02X", $0) }
            .joined()
    }
}

extension segment_command {
    func segnameString(swap: Bool) -> String {
        return int8TupleToString(segname, swap: swap)
    }
}

extension segment_command_64 {
    func segnameString(swap: Bool) -> String {
        return int8TupleToString(segname, swap: swap)
    }
}

extension uuid_command {
    func uuidString(swap: Bool) -> String {
        let hexString = uint8TupleToHexString(uuid, swap: swap)
        return [8, 4, 4, 4, 12]
            .reduce(into: (Array<String.SubSequence>(), hexString.startIndex)) { acc, count in
                let limitIndex = hexString.index(acc.1, offsetBy: count)
                let substring = hexString[acc.1..<limitIndex]
                acc = ((acc.0 + [substring]), limitIndex)
            }
            .0
            .joined(separator: "-")
    }
}

extension section {
    func sectnameString(swap: Bool) -> String {
        return int8TupleToString(sectname, swap: swap)
    }

    func segnameString(swap: Bool) -> String {
        return int8TupleToString(segname, swap: swap)
    }
}

extension section_64 {
    func sectnameString(swap: Bool) -> String {
        return int8TupleToString(sectname, swap: swap)
    }

    func segnameString(swap: Bool) -> String {
        return int8TupleToString(segname, swap: swap)
    }
}

private func cpuTypeToString(_ cputype: Int32) -> String? {
    if cputype & CPU_TYPE_ARM == CPU_TYPE_ARM {
        return "CPU_TYPE_ARM"
    }
    if cputype & CPU_TYPE_ARM64 == CPU_TYPE_ARM64 {
        return "CPU_TYPE_ARM64"
    }
    if cputype & CPU_TYPE_X86 == CPU_TYPE_X86 {
        return "CPU_TYPE_X86"
    }
    if cputype & CPU_TYPE_X86_64 == CPU_TYPE_X86_64 {
        return "CPU_TYPE_X86_64"
    }
    if cputype & CPU_TYPE_POWERPC == CPU_TYPE_POWERPC {
        return "CPU_TYPE_POWERPC"
    }
    if cputype & CPU_TYPE_POWERPC64 == CPU_TYPE_POWERPC64 {
        return "CPU_TYPE_POWERPC64"
    }
    // yes, should be enough 😅
    return nil
}

extension mach_header {
    var cputypeString: String? {
        return cpuTypeToString(cputype)
    }
}

extension mach_header_64 {
    var cputypeString: String? {
        return cpuTypeToString(cputype)
    }
}
