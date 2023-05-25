import Foundation

struct RuntimeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

struct Parser {
    let path: String

    init(path: String) {
        self.path = path
    }

    func parse() throws -> Image {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw RuntimeError("Couldn't even create a handle for reading file at path: \(path)")
        }
        defer {
            try! handle.close()
        }

        let (magic, header, shouldSwap) = try parseHeader(with: handle)

        if case .fat_header(let fat_header) = header {
            let sixtyFourBits = magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64
            let archs = try parseArchs(header: fat_header, with: handle, sixtyFour: sixtyFourBits, swap: shouldSwap)
            return Image(path: path, header: header, archs: archs)
        } else {
            let cmds = try parseLoadCommands(header: header, with: handle, swap: shouldSwap)
            let loadCommands = cmds.map { LoadCommand(cmd: $0, context: .init(shouldSwap: shouldSwap)) }
            return Image(path: path, header: header, archs: [.init(magic: magic, header: header, loadCommands: loadCommands)])
        }
    }

    private func parseHeader(with handle: FileHandle, startOffset: UInt64 = .zero) throws -> (magic: UInt32, header: Image.Header, swap: Bool) {
        let magic = try handle.parse(UInt32.self)

        try handle.seek(toOffset: startOffset)

        switch magic {
        case MH_MAGIC, MH_CIGAM:
            let shouldSwap = magic == MH_CIGAM
            let header = try handle.parse(mach_header.self, swap: shouldSwap)
            return (magic, .mach_header(header), shouldSwap)
        case MH_MAGIC_64, MH_CIGAM_64:
            let shouldSwap = magic == MH_CIGAM_64
            let header = try handle.parse(mach_header_64.self, swap: shouldSwap)
            return (magic, .mach_header_64(header), shouldSwap)
        case FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64:
            let shouldSwap = magic == FAT_CIGAM || magic == FAT_CIGAM_64
            let header = try handle.parse(fat_header.self, swap: shouldSwap)
            return (magic, .fat_header(header), shouldSwap)
        default:
            throw RuntimeError("Unknown image type.")
        }
    }

    private func parseArchs(header: fat_header, with handle: FileHandle, sixtyFour: Bool, swap: Bool) throws -> [Image.Arch] {
        let startOffset = try handle.offset()

        var archs: [Image.Arch] = []
        var nextArchOffset: UInt64 = startOffset
        for _ in 0 ..< header.nfat_arch {
            let seekOffset: UInt64
            if sixtyFour {
                let arch = try handle.parse(fat_arch_64.self, swap: swap)
                seekOffset = arch.offset
                nextArchOffset += UInt64(MemoryLayout<fat_arch_64>.size)
            } else {
                let arch = try handle.parse(fat_arch.self, swap: swap)
                seekOffset = UInt64(arch.offset)
                nextArchOffset += UInt64(MemoryLayout<fat_arch>.size)
            }

            try handle.seek(toOffset: seekOffset)

            let (magic, header, swapFromHeader) = try parseHeader(with: handle, startOffset: seekOffset)
            let cmds = try parseLoadCommands(header: header, with: handle, swap: swapFromHeader)
            let loadCommands = cmds.map { LoadCommand(cmd: $0, context: .init(shouldSwap: swapFromHeader)) }
            archs.append(.init(magic: magic, header: header, loadCommands: loadCommands))

            try handle.seek(toOffset: nextArchOffset)
        }

        return archs
    }

    private func parseLoadCommands(header: Image.Header, with handle: FileHandle, swap: Bool) throws -> [LoadCommand.Cmd] {
        let ncmds, sizeofcmds: UInt32
        switch header {
        case .mach_header(let header):
            ncmds = header.ncmds
            sizeofcmds = header.sizeofcmds
        case .mach_header_64(let header):
            ncmds = header.ncmds
            sizeofcmds = header.sizeofcmds
        case .fat_header:
            assertionFailure("You shouldn't be in this case for a FAT header.")
            return []
        }
        guard let readData = try handle.read(upToCount: Int(sizeofcmds)) else {
            throw RuntimeError("Not enough data to read load commands")
        }
        let data = swap ? readData.swapEndian : readData
        let lcSize = MemoryLayout<load_command>.size // 8 bytes
        var offset: Int = .zero
        var commands: [LoadCommand.Cmd] = []
        for _ in 0 ..< ncmds {
            let rawLoadCommandData = data[offset ..< (offset + lcSize)]
            let rawLoadCommand = rawLoadCommandData.withUnsafeBytes { $0.load(as: load_command.self) }
            let loadCommandData = data[offset ..< (offset + Int(rawLoadCommand.cmdsize))]
            let loadCommand = parseSingleLoadCommand(data: data, offset: offset, cmdData: loadCommandData, cmd: rawLoadCommand.cmd, swap: swap)
            offset += Int(rawLoadCommand.cmdsize)
            commands.append(loadCommand)
        }
        return commands
    }

    private func parseSingleLoadCommand(data: Data, offset: Int, cmdData: Data, cmd: UInt32, swap: Bool) -> LoadCommand.Cmd {
        switch cmd {
        case UInt32(MachO.LC_SEGMENT):
            return parseSegmentLoadCommand(data: data, offset: offset, cmdData: cmdData)
        case UInt32(MachO.LC_SEGMENT_64):
            return parse64SegmentLoadCommand(data: data, offset: offset, cmdData: cmdData)
        case UInt32(MachO.LC_UUID):
            return .LC_UUID(cmdData.withUnsafeBytes { $0.load(as: uuid_command.self) })
        case MachO.LC_DYLD_INFO_ONLY:
            return .LC_DYLD_INFO_ONLY(cmdData.withUnsafeBytes { $0.load(as: dyld_info_command.self) })
        case UInt32(MachO.LC_SYMTAB):
            return .LC_SYMTAB(cmdData.withUnsafeBytes { $0.load(as: symtab_command.self) })
        case UInt32(MachO.LC_DYSYMTAB):
            return .LC_DYSYMTAB(cmdData.withUnsafeBytes { $0.load(as: dysymtab_command.self) })
        case UInt32(MachO.LC_LOAD_DYLINKER):
            return parseLoadDylinkerCommand(data: data, offset: offset, cmdData: cmdData, swap: swap)
        case UInt32(MachO.LC_VERSION_MIN_MACOSX):
            return .LC_VERSION_MIN_MACOSX(cmdData.withUnsafeBytes { $0.load(as: version_min_command.self) })
        case UInt32(MachO.LC_SOURCE_VERSION):
            return .LC_SOURCE_VERSION(cmdData.withUnsafeBytes { $0.load(as: source_version_command.self) })
        case MachO.LC_MAIN:
            return .LC_MAIN(cmdData.withUnsafeBytes { $0.load(as: entry_point_command.self) })
        case UInt32(MachO.LC_LOAD_DYLIB):
            return parseLoadDylibCommand(data: data, offset: offset, cmdData: cmdData, swap: swap)
        case UInt32(MachO.LC_FUNCTION_STARTS):
            return .LC_FUNCTION_STARTS(cmdData.withUnsafeBytes { $0.load(as: linkedit_data_command.self) })
        case UInt32(MachO.LC_DATA_IN_CODE):
            return .LC_DATA_IN_CODE(cmdData.withUnsafeBytes { $0.load(as: linkedit_data_command.self) })
        case UInt32(MachO.LC_UNIXTHREAD):
            return .LC_UNIXTHREAD(cmdData.withUnsafeBytes { $0.load(as: thread_command.self) })
        case UInt32(MachO.LC_CODE_SIGNATURE):
            return .LC_CODE_SIGNATURE(cmdData.withUnsafeBytes { $0.load(as: linkedit_data_command.self) })
        case UInt32(MachO.LC_BUILD_VERSION):
            return .LC_BUILD_VERSION(cmdData.withUnsafeBytes { $0.load(as: build_version_command.self) })
        default:
            return .unknown(cmd: cmd, data: cmdData)
        }
    }

    private func parseSegmentLoadCommand(data: Data, offset: Int, cmdData: Data) -> LoadCommand.Cmd {
        let segment = cmdData.withUnsafeBytes { $0.load(as: segment_command.self) }
        var sections: [section] = []

        if segment.nsects > 0 {
            let sectionSize = MemoryLayout<section>.size

            for i in 0 ..< segment.nsects {
                let sectionOffset = offset + MemoryLayout<segment_command>.size + Int(i) * sectionSize
                let sectionData = data[sectionOffset ..< (sectionOffset + sectionSize)]
                let section = sectionData.withUnsafeBytes { $0.load(as: MachO.section.self) }
                sections.append(section)
            }
        }

        return .LC_SEGMENT(segment: segment, sections: sections)
    }

    private func parse64SegmentLoadCommand(data: Data, offset: Int, cmdData: Data) -> LoadCommand.Cmd {
        let segment = cmdData.withUnsafeBytes { $0.load(as: segment_command_64.self) }
        var sections: [section_64] = []

        if segment.nsects > 0 {
            let sectionSize = MemoryLayout<section_64>.size

            for i in 0 ..< segment.nsects {
                let sectionOffset = offset + MemoryLayout<segment_command_64>.size + Int(i) * sectionSize
                let sectionData = data[sectionOffset ..< (sectionOffset + sectionSize)]
                let section = sectionData.withUnsafeBytes { $0.load(as: section_64.self) }
                sections.append(section)
            }
        }

        return .LC_SEGMENT_64(segment: segment, sections: sections)
    }

    private func parseLoadDylibCommand(data: Data, offset: Int, cmdData: Data, swap: Bool) -> LoadCommand.Cmd {
        let command = cmdData.withUnsafeBytes { $0.load(as: dylib_command.self) }
        let dylibName = retrieve(loadCommandString: command.dylib.name, from: data, offset: offset, size: Int(command.cmdsize), swap: swap)
        return .LC_LOAD_DYLIB(cmd: command, dylibName: dylibName, offset: command.dylib.name.offset)
    }

    private func parseLoadDylinkerCommand(data: Data, offset: Int, cmdData: Data, swap: Bool) -> LoadCommand.Cmd {
        let command = cmdData.withUnsafeBytes { $0.load(as: dylinker_command.self) }
        let linker = retrieve(loadCommandString: command.name, from: data, offset: offset, size: Int(command.cmdsize), swap: swap)
        return .LC_LOAD_DYLINKER(cmd: command, linker: linker, offset: command.name.offset)
    }
}

extension Parser {
    private func retrieve(loadCommandString lc_str: lc_str, from data: Data, offset: Int, size: Int, swap: Bool) -> String {
        let stringOffset = offset + Int(lc_str.offset)
        let startIndex = data.index(data.startIndex, offsetBy: stringOffset)
        let endIndex = data.index(startIndex, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
        let stringData = data[startIndex ..< endIndex]
        let inOrderStringData = swap ? stringData.swapEndian : stringData
        return inOrderStringData.withUnsafeBytes { buffer in
            guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return "<invalid_string>"
            }
            return String(cString: pointer)
        }
    }
}
