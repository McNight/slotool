import ArgumentParser
import Foundation

@main
struct slotool: ParsableCommand {
    static let configuration = CommandConfiguration(helpNames: [.long, .customShort("?")])

    @Flag(name: [.customShort("h")], help: "print the mach header")
    var machHeader: Bool = false

    @Flag(name: [.customShort("l")], help: "print the load commands")
    var loadCommands: Bool = false

    @Flag(name: [.customShort("L")], help: "print shared libraries used")
    var printSharedLibs: Bool = false

    @Argument
    var inputFile: String

    mutating func run() throws {
        let parser = Parser(path: inputFile)

        var options: PrintingOptions = []

        if machHeader {
            options.insert(.machHeader)
        }
        if loadCommands {
            options.insert(.loadCommands)
        }
        if printSharedLibs {
            options.insert(.sharedLibs)
        }

        guard !options.isEmpty else {
            throw ValidationError("Please use an option. See --help for available options.")
        }

        let image = try parser.parse()

        Printer.print(image: image, options: options)
    }
}
