import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: build-icns.swift <iconset> <output>\n".utf8))
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries = [
    (type: "ic07", file: "icon_128x128.png"),
    (type: "ic08", file: "icon_256x256.png"),
    (type: "ic09", file: "icon_512x512.png"),
    (type: "ic10", file: "icon_512x512@2x.png")
]

func bigEndianBytes(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
}

var body = Data()
for entry in entries {
    let png = try Data(contentsOf: iconset.appendingPathComponent(entry.file))
    body.append(Data(entry.type.utf8))
    body.append(bigEndianBytes(UInt32(png.count + 8)))
    body.append(png)
}

var icon = Data("icns".utf8)
icon.append(bigEndianBytes(UInt32(body.count + 8)))
icon.append(body)
try icon.write(to: output, options: .atomic)
