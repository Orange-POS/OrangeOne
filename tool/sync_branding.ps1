$ErrorActionPreference = 'Stop'
$brandingRoot = Split-Path -Parent $PSScriptRoot
$brandingSource = Join-Path $brandingRoot 'assets/branding/app_logo.png'
$brandingTargets = @(
    'android/app/src/main/res/drawable-nodpi/app_logo.png',
    'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@1x.png',
    'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png',
    'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png'
)
foreach ($brandingTarget in $brandingTargets) {
    Copy-Item -LiteralPath $brandingSource -Destination (Join-Path $brandingRoot $brandingTarget)
}
