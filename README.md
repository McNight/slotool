# slotool (Swifty Light otool)

(Very) limited `otool` like tool written in Swift.

For educational purposes only. Obviously don't use this and prefer the more reliable `otool` 

I wanted to play around with the Mach-O format and try to parse it to retrieve various infos like `otool` does.

## Usage

Only supports printing the Mach header and load commands.

```console
USAGE: slotool [-h] [-l] <input-file>

ARGUMENTS:
  <input-file>

OPTIONS:
  -h                      print the mach header
  -l                      print the load commands
  -?, --help              Show help information.
```

## Examples

```console
> slotool -l /bin/ls
> Image</bin/ls>: FAT Image
Arch 0: Little Endian, 64, CPU_TYPE_X86
Arch 1: Little Endian, 64, CPU_TYPE_ARM
Load commands for Arch 0
Load command 0
     cmd LC_SEGMENT_64
 cmdsize 72
 segname __PAGEZERO
  vmaddr 0x0
  vmsize 0x100000000
 fileoff 0
filesize 0
 maxprot 0x0
initprot 0x0
  nsects 0
   flags 0
Load command 1
     cmd LC_SEGMENT_64
 cmdsize 552
 segname __TEXT
  vmaddr 0x100000000
  vmsize 0x8000
 fileoff 0
filesize 32768
 maxprot 0x5
initprot 0x5
  nsects 6
   flags 0
[...]
Load command 13
    cmd LC_LOAD_DYLIB
cmdsize 48
   name /usr/lib/libutil.dylib (offset 24)
Load command 14
    cmd LC_LOAD_DYLIB
cmdsize 56
   name /usr/lib/libncurses.5.4.dylib (offset 24)
Load command 15
    cmd LC_LOAD_DYLIB
cmdsize 56
   name /usr/lib/libSystem.B.dylib (offset 24)
[...]
```

```console
> slotool -h /Applications/VLC_PPC.app/Contents/MacOS/VLC
> Image</Applications/VLC_PPC.app/Contents/MacOS/VLC>: Single Image, Big Endian, CPU_TYPE_POWERPC
Mach header
     magic  cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags
0xfeedface       18          0  0x00           2    17       1664 0x85
```

## License

JMSCDGL (Je M'en Soucie Comme D'une Guigne License) = do what you want with it
