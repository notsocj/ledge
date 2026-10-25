import AppKit
// swift site/crop.swift <snapshot folder> <assets folder> name=snapshot ...
// Crops each transparent snapshot to the island (its non-transparent pixels) and prints its size in points.
let args = CommandLine.arguments
let source = URL(fileURLWithPath: args[1]), assets = URL(fileURLWithPath: args[2])
for pair in args.dropFirst(3) {
    let parts = pair.split(separator: "=").map(String.init)
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: source.appending(path: parts[1] + ".png")))!
    var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    let crop = rep.cgImage!.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
    let out = NSBitmapImageRep(cgImage: crop)
    try! out.representation(using: .png, properties: [:])!.write(to: assets.appending(path: parts[0] + ".png"))
    print(parts[0], crop.width / 2, "x", crop.height / 2)
}
