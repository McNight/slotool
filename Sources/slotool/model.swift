import Foundation

struct LoadCommand {
    enum Cmd {
        case LC_SEGMENT(segment: segment_command, sections: [section])
        case LC_SEGMENT_64(segment: segment_command_64, sections: [section_64])
        case LC_UUID(uuid_command)
        case LC_DYLD_INFO_ONLY(dyld_info_command)
        case LC_SYMTAB(symtab_command)
        case LC_DYSYMTAB(dysymtab_command)
        case LC_LOAD_DYLINKER(cmd: dylinker_command, linker: String, offset: UInt32)
        case LC_VERSION_MIN_MACOSX(version_min_command)
        case LC_SOURCE_VERSION(source_version_command)
        case LC_MAIN(entry_point_command)
        case LC_LOAD_DYLIB(cmd: dylib_command, dylibName: String, offset: UInt32)
        case LC_LOAD_WEAK_DYLIB(cmd: dylib_command, dylibName: String, offset: UInt32)
        case LC_FUNCTION_STARTS(linkedit_data_command)
        case LC_DATA_IN_CODE(linkedit_data_command)
        case LC_UNIXTHREAD(thread_command)
        case LC_CODE_SIGNATURE(linkedit_data_command)
        case LC_BUILD_VERSION(build_version_command)
        case unknown(cmd: UInt32, data: Data) // or lazy to add
    }
    struct Context {
        let shouldSwap: Bool
    }

    let cmd: Cmd
    let context: Context
}

struct Image {
    enum Header {
        case mach_header(mach_header)
        case mach_header_64(mach_header_64)
        case fat_header(fat_header)

        var nfat_arch: UInt32 {
            switch self {
            case .mach_header, .mach_header_64:
                return 1
            case .fat_header(let header):
                return header.nfat_arch
            }
        }
    }
    struct Arch {
        let magic: UInt32
        let header: Header
        let loadCommands: [LoadCommand]
    }
    let path: String
    let header: Header
    let archs: [Arch]
}

extension Image: CustomStringConvertible {
    var description: String {
        let imageType: String
        switch header {
        case .mach_header, .mach_header_64:
            imageType = "Single Image"
        case .fat_header:
            imageType = "FAT Image"
        }
        var output: String = "Image<\(path)>: \(imageType)"
        if header.nfat_arch == 1 {
            output += ", \(archs[0].description)"
        } else {
            for (index, arch) in archs.enumerated() {
                output += "\nArch \(index): \(arch)"
            }
        }
        return output
    }
}

extension Image.Arch {
    var cputypeString: String? {
        switch header {
        case .mach_header(let header):
            return header.cputypeString
        case .mach_header_64(let header):
            return header.cputypeString
        default:
            return nil
        }
    }
}

extension Image.Arch: CustomStringConvertible {
    var description: String {
        let archType: String
        switch magic {
        case MH_MAGIC:
            archType = "Little Endian"
        case MH_MAGIC_64:
            archType = "Little Endian, 64"
        case MH_CIGAM:
            archType = "Big Endian"
        case MH_CIGAM_64:
            archType = "Big Endian, 64"
        case FAT_MAGIC:
            archType = "Little Endian FAT Archive"
        case FAT_MAGIC_64:
            archType = "Little Endian FAT Archive, 64"
        case FAT_CIGAM:
            archType = "Big Endian FAT Archive"
        case FAT_CIGAM_64:
            archType = "Big Endian FAT Archive, 64"
        default:
            archType = "Unknown"
        }
        if let cputypeString {
            return "\(archType), \(cputypeString)"
        }
        return archType
    }
}

extension LoadCommand: CustomStringConvertible {
    var description: String {
        switch cmd {
        case let .LC_SEGMENT(command, sections):
            return """
                 cmd LC_SEGMENT
             cmdsize \(command.cmdsize)
             segname \(command.segnameString(swap: context.shouldSwap))
              vmaddr 0x\(String(command.vmaddr, radix: 16))
              vmsize 0x\(String(command.vmsize, radix: 16))
             fileoff \(command.fileoff)
            filesize \(command.filesize)
             maxprot 0x\(String(command.maxprot, radix: 16))
            initprot 0x\(String(command.initprot, radix: 16))
              nsects \(command.nsects)
               flags \(command.flags)
            """
            +
            sections.reduce(into: "", { acc, section in acc.append("\n\(section.description(swap: context.shouldSwap))") })
        case let .LC_SEGMENT_64(command, sections):
            return """
                 cmd LC_SEGMENT_64
             cmdsize \(command.cmdsize)
             segname \(command.segnameString(swap: context.shouldSwap))
              vmaddr 0x\(String(command.vmaddr, radix: 16))
              vmsize 0x\(String(command.vmsize, radix: 16))
             fileoff \(command.fileoff)
            filesize \(command.filesize)
             maxprot 0x\(String(command.maxprot, radix: 16))
            initprot 0x\(String(command.initprot, radix: 16))
              nsects \(command.nsects)
               flags \(command.flags)
            """
            +
            sections.reduce(into: "", { acc, section in acc.append("\n\(section.description(swap: context.shouldSwap))") })
        case .LC_UUID(let command):
            return """
                cmd LC_UUID
            cmdsize \(command.cmdsize)
               uuid \(command.uuidString(swap: context.shouldSwap))
            """
        case let .LC_LOAD_DYLIB(command, dylibName, offset), let .LC_LOAD_WEAK_DYLIB(command, dylibName, offset):
            let cmdString: String
            // meh
            if case .LC_LOAD_DYLIB = cmd {
                cmdString = "LC_LOAD_DYLIB"
            } else {
                cmdString = "LC_LOAD_WEAK_DYLIB"
            }
            return """
                cmd \(cmdString)
            cmdsize \(command.cmdsize)
               name \(dylibName) (offset \(offset))
            """
        case .LC_DYLD_INFO_ONLY(let command):
            return """
                       cmd LC_DYLD_INFO_ONLY
                   cmdsize \(command.cmdsize)
                rebase_off \(command.rebase_off)
               rebase_size \(command.rebase_size)
                  bind_off \(command.bind_off)
                 bind_size \(command.bind_size)
             weak_bind_off \(command.weak_bind_off)
            weak_bind_size \(command.weak_bind_size)
             lazy_bind_off \(command.lazy_bind_off)
            lazy_bind_size \(command.lazy_bind_size)
                export_off \(command.export_off)
               export_size \(command.export_size)
            """
        case .LC_SYMTAB(let command):
            return """
                cmd LC_SYMTAB
            cmdsize \(command.cmdsize)
             symoff \(command.symoff)
              nsyms \(command.nsyms)
             stroff \(command.stroff)
            strsize \(command.strsize)
            """
        case .LC_DYSYMTAB(let command):
            return """
                       cmd LC_DYSYMTAB
                   cmdsize \(command.cmdsize)
                 ilocalsym \(command.ilocalsym)
                 nlocalsym \(command.nlocalsym)
                iextdefsym \(command.iextdefsym)
                nextdefsym \(command.nextdefsym)
                 iundefsym \(command.iundefsym)
                 nundefsym \(command.nundefsym)
                    tocoff \(command.tocoff)
                      ntoc \(command.ntoc)
                 modtaboff \(command.modtaboff)
                   nmodtab \(command.nmodtab)
              extrefsymoff \(command.extrefsymoff)
               nextrefsyms \(command.nextrefsyms)
            indirectsymoff \(command.indirectsymoff)
             nindirectsyms \(command.nindirectsyms)
                 extreloff \(command.extreloff)
                   nextrel \(command.nextrel)
                 locreloff \(command.locreloff)
                   nlocrel \(command.locreloff)
            """
        case let .LC_LOAD_DYLINKER(command, linker, offset):
            return """
                cmd LC_LOAD_DYLINKER
            cmdsize \(command.cmdsize)
               name \(linker) \(offset)
            """
        case .LC_VERSION_MIN_MACOSX(let command):
            let vxNibble = UInt8((command.version & 0xFFFF0000) >> 16)
            let vyNibble = UInt8((command.version & 0x0000FF00) >> 8)
            let vzNibble = UInt8(command.version & 0x000000FF)
            let sdkxNibble = UInt8((command.sdk & 0xFFFF0000) >> 16)
            let sdkyNibble = UInt8((command.sdk & 0x0000FF00) >> 8)
            let sdkzNibble = UInt8(command.sdk & 0x000000FF)
            return """
                cmd LC_VERSION_MIN_MACOSX
            cmdsize \(command.cmdsize)
            version \(vxNibble.stringOrDiscard())\(vyNibble.stringOrDiscard(prefix: "."))\(vzNibble.stringOrDiscard(prefix: "."))
                sdk \(sdkxNibble.stringOrDiscard())\(sdkyNibble.stringOrDiscard(prefix: "."))\(sdkzNibble.stringOrDiscard(prefix: "."))
            """
        case .LC_SOURCE_VERSION(let command):
            return """
                cmd LC_SOURCE_VERSION
            cmdsize \(command.cmdsize)
            version \(command.version)
            """
        case .LC_MAIN(let command):
            return """
                  cmd LC_MAIN
              cmdsize \(command.cmdsize)
             entryoff \(command.entryoff)
            stacksize \(command.stacksize)
            """
        case .LC_FUNCTION_STARTS(let command), .LC_DATA_IN_CODE(let command):
            let cmdString: String
            // meh
            if case .LC_FUNCTION_STARTS = cmd {
                cmdString = "LC_FUNCTION_STARTS"
            } else {
                cmdString = "LC_DATA_IN_CODE"
            }
            return """
                 cmd \(cmdString)
             cmdsize \(command.cmdsize)
             dataoff \(command.dataoff)
            datasize \(command.datasize)
            """
        case .LC_UNIXTHREAD(let command):
            return """
                cmd LC_UNIXTHREAD
            cmdsize \(command.cmdsize)
            """
        case .LC_CODE_SIGNATURE(let command):
            return """
                 cmd LC_CODE_SIGNATURE
             cmdsize \(command.cmdsize)
             dataoff \(command.dataoff)
            datasize \(command.datasize)
            """
        case .LC_BUILD_VERSION(let command):
            return """
                cmd LC_BUILD_VERSION
            cmdsize \(command.cmdsize)
             ntools \(command.ntools)
            """
        default:
            let mirror = Mirror(reflecting: self)
            let enumName = mirror.children.first?.label ?? "UNKNOWN_COMMAND"
            guard !mirror.children.isEmpty else {
                return enumName
            }
            return """
              cmd \(enumName)
            value \(mirror.children[mirror.children.startIndex].value)
            """
        }
    }
}

extension section {
    func description(swap: Bool) -> String {
        """
        Section
          sectname \(sectnameString(swap: swap))
           segname \(segnameString(swap: swap))
              addr 0x\(String(addr, radix: 16))
              size 0x\(String(size, radix: 16))
            offset \(offset)
             align \(align)
            reloff \(reloff)
            nreloc \(nreloc)
             flags 0x\(String(flags, radix: 16))
         reserved1 \(reserved1) (index into indirect symbol table)
         reserved2 \(reserved2)
        """
    }
}

extension section_64 {
    func description(swap: Bool) -> String {
        """
        Section
          sectname \(sectnameString(swap: swap))
           segname \(segnameString(swap: swap))
              addr 0x\(String(addr, radix: 16))
              size 0x\(String(size, radix: 16))
            offset \(offset)
             align \(align)
            reloff \(reloff)
            nreloc \(nreloc)
             flags 0x\(String(flags, radix: 16))
         reserved1 \(reserved1) (index into indirect symbol table)
         reserved2 \(reserved2)
        """
    }
}

private extension UInt8 {
    func stringOrDiscard(prefix: String? = nil) -> String {
        return self != 0 ? "\(prefix ?? "")\(self)" : ""
    }
}
