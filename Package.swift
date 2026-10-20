// swift-tools-version:5.9
import PackageDescription

// Le Info.plist est incrusté dans l'exécutable (section __TEXT,__info_plist) : c'est lui qui
// porte le numéro de version.
let infoPlist = "\(Context.packageDirectory)/Resources/Info.plist"

let package = Package(
    name: "Developpeur",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mcp-developpeur", targets: ["MCPDeveloppeur"]),
    ],
    targets: [
        .target(name: "DeveloppeurKit"),
        .executableTarget(
            name: "MCPDeveloppeur",
            dependencies: ["DeveloppeurKit"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
        .testTarget(
            name: "DeveloppeurKitTests",
            dependencies: ["DeveloppeurKit"]
        ),
    ]
)
