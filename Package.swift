// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ImageVideoCropper",
    platforms: [.iOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ImageVideoCropper",
            targets: ["ImageVideoCropper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/harikrishnabista7/TOCropViewController.git", branch: "main")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ImageVideoCropper",
            dependencies: [
                .product(name: "TOCropViewController", package: "TOCropViewController")
            ]
        ),
    ]
)
