load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_bundle",
)
load("//build-system/bazel-utils:plist_fragment.bzl",
    "plist_fragment",
)

filegroup(
    name = "LiquidLensMetalSources",
    srcs = glob([
        "Metal/**/*.metal",
        "Metal/**/*.h",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "LiquidLensMetalSourcesBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.LiquidLensMetalSources</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>LiquidLens</string>
    """
)

apple_resource_bundle(
    name = "LiquidLensMetalSourcesBundle",
    infoplists = [
        ":LiquidLensMetalSourcesBundleInfoPlist",
    ],
    resources = [
        ":LiquidLensMetalSources",
    ],
)

objc_library(
    name = "LiquidLensSharedTypes",
    module_name = "LiquidLensSharedTypes",
    enable_modules = True,
    hdrs = glob([
        "Metal/**/*.h",
    ]),
    includes = [
        "Metal",
    ],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "LiquidLens",
    module_name = "LiquidLens",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    data = [
        ":LiquidLensMetalSourcesBundle",
    ],
    deps = [
        ":LiquidLensSharedTypes",
        "//submodules/Display",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
