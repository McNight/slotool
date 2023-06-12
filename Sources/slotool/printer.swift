import Foundation

struct PrintingOptions: OptionSet {
    static let machHeader   = PrintingOptions(rawValue: 1 << 0)
    static let loadCommands = PrintingOptions(rawValue: 1 << 1)
    static let sharedLibs   = PrintingOptions(rawValue: 1 << 2)

    let rawValue: Int
}

enum Printer {
    static func print(image: Image, options: PrintingOptions) {
        Swift.print(image)

        if options.contains(.machHeader) {
            Swift.print("Mach header")

            switch image.header {
            case .mach_header(let header):
                printHeader(
                    magicToTest: FAT_CIGAM,
                    magic: header.magic,
                    cputype: header.cputype,
                    cpusubtype: header.cpusubtype,
                    caps: .zero,
                    filetype: header.filetype,
                    ncmds: header.ncmds,
                    sizeofcmds: header.sizeofcmds,
                    flags: header.flags
                )
            case .mach_header_64(let header):
                printHeader(
                    magicToTest: FAT_CIGAM_64,
                    magic: header.magic,
                    cputype: header.cputype,
                    cpusubtype: header.cpusubtype,
                    caps: .zero,
                    filetype: header.filetype,
                    ncmds: header.ncmds,
                    sizeofcmds: header.sizeofcmds,
                    flags: header.flags
                )
            case .fat_header(let header):
                printFatHeader(magic: header.magic, nfat_arch: header.nfat_arch)
            }
        }

        if options.contains(.loadCommands) {
            if image.header.nfat_arch > 1 {
                for (index, arch) in image.archs.enumerated() {
                    Swift.print("Load commands for Arch \(index)")
                    printLoadCommands(for: arch)
                }
            } else {
                Swift.print("Load commands")
                printLoadCommands(for: image.archs[0])
            }
        }

        if options.contains(.sharedLibs) {
            image.archs.forEach { printSharedLibraries(for: $0) }
        }
    }

    private static func printLoadCommands(for arch: Image.Arch) {
        for (index, loadCommand) in arch.loadCommands.enumerated() {
            Swift.print("Load command \(index)")
            Swift.print(loadCommand)
        }
    }

    private static func printSharedLibraries(for arch: Image.Arch) {
        let libs = arch.loadCommands.compactMap { loadCommand in
            switch loadCommand.cmd {
            case .LC_LOAD_DYLIB(_, let dylib, _):
                return dylib
            case .LC_LOAD_WEAK_DYLIB(_, let dylib, _):
                return dylib
            default:
                return nil
            }
        }
        if libs.isEmpty {
            Swift.print("No load dylib load command found")
        } else {
            libs.forEach { Swift.print($0) }
        }
    }

    private static func printFatHeader(
        magic: UInt32,
        nfat_arch: UInt32
    ) {
        Swift.print("Fat headers")
        Swift.print("fat_magic 0x\(String(magic, radix: 16))")
        Swift.print("nfat_arch \(nfat_arch)")
        // TODO: Print the rest, but we need to store archs fat_arch/fat_arch_64
    }

    private static func printHeader(
        magicToTest: UInt32,
        magic: UInt32,
        cputype: Int32,
        cpusubtype: Int32,
        caps: UInt32,
        filetype: UInt32,
        ncmds: UInt32,
        sizeofcmds: UInt32,
        flags: UInt32
    ) {
        Swift.print("     magic  cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags")

        let inOrderMagic = magic == magicToTest ? CFSwapInt32(magic) : magic // probably unnecessary
        Swift.print("0x\(String(inOrderMagic, radix: 16))", terminator: "       ")
        Swift.print(cputype, terminator: "          ")
        Swift.print(cpusubtype, terminator: "  ")
        Swift.print("0x00", terminator: "           ") // caps
        Swift.print(filetype, terminator: "    ")
        Swift.print(ncmds, terminator: "       ")
        Swift.print(sizeofcmds, terminator: " ")
        Swift.print("0x\(String(flags, radix: 16))")
    }
}
