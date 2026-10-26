// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "DragTwoZero",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DragTwoZero", targets: ["DragTwoZero"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .executableTarget(name: "DragTwoZero", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "DragTwoZeroTests", dependencies: ["DragTwoZero"])
    ]
)
