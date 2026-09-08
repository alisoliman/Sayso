# Native app icon

Sayso uses `Sayso/AppIcon.icon`, authored in Apple's Icon Composer from the original seven-capsule waveform. The foreground remains vector artwork; the system supplies the mask, lighting, and appearance effects. The app target already selects the name `AppIcon`, and its synchronized Sayso folder includes the native document.

The default appearance retains the warm background and muted purple waveform. Dark appearance uses the app's pale-violet accent. The monochrome variation uses white artwork so the system can apply a person's selected tint. Group shadow opacity is 0.16 and translucency is 0.12; the artwork contains no baked lighting.

The native document was first created, imported, and saved through Icon Composer 1.6 (99.1). Dark and Mono variations were also authored through its UI. Exact brand color values were then adjusted in those existing native fields and validated with Apple's `ictool` renderer. No unobserved manifest fields were introduced.

## Verification boundary

On 8 September 2026, the original candidate was rendered at 1024 pixels and independently reviewed at a native 60-point, 3× Home Screen scale. Default, Dark, ClearLight, ClearDark, and TintedLight were readable. TintedDark's default purple was subdued; Apple's documented tint-color 0.25 / strength 0.75 example produced a legible gold variant. A comparison with translucency disabled did not materially improve the purple rendition, so the native material was retained.

The 14 render commands, source hashes, PNG hashes, and review observations are in `.build/icon-composer-review/review.json`. They establish historical Icon Composer 1.6 rendering. The installed iOS 27 Home Screen review below is separate evidence; continuous icon motion and broader wallpaper/tint combinations remain unverified.

The unsigned arm64 iPhone Release build passed with Xcode 26.6 / SDK 26.5 and no warnings. Its asset compiler explicitly consumed `Sayso/AppIcon.icon`; the resulting bundle selects `AppIcon` and includes compiled icon resources. App, keyboard, and Live Activity executable hashes remain identical to the preceding Release, with no DEBUG test flags. Evidence: `.build/build-device-release-native-icon.log` and `.build/native-icon-release-inspection.json`. No additional unit/UI test passes are claimed for this asset-only change.

Source SHA-256:

- `icon.json`: `323179aad60362b3098b2921f2234a5cfccd5b4704e581d3e0b78453b5ff316d`
- `Assets/Sayso-Wave.svg`: `3bdad284fc86f0e76326727518d42ef56446671906050bc80cfc9e0a40c62b7f`

The existing asset-catalog PNG and its generator remain preserved. Apple's current guidance says Xcode uses the matching Icon Composer file in place of the asset-catalog icon; the PNG is not treated as a guaranteed runtime fallback. See [Apple's Icon Composer guide](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

## Native iOS 27 packaging evidence

The actual Xcode 27 beta 6 / `27A5252f` device Release was inspected with Apple's `assetutil`. Its bundle targets iOS 27 and selects `AppIcon`; the catalog identifies platform 27.0 and contains native Light, Dark and Tintable `IconImageStack` entries, each with two logical layers and a vector waveform. The native stacks have no flattened composite image. Compiled colors and group material settings match the source, and the waveform vector digest matches the historical native catalog. Raster compatibility renditions coexist with those native stacks; the result is not bitmap-only.

[Inspection and hashes](../.build/ios27-native-icon-inspection.json) records the catalog SHA-256 `a7880183aa8a7ddddc15cc8f344523b50127c50e91a91f95dc166d5e56468027`, SDK 27.0 / `24A5422a`, and the unchanged source hashes above. This inspection establishes packaging. It does not by itself establish the Home Screen appearance reviewed below, and it adds no unit/UI test passes.

## Installed iOS 27 Home Screen review

On 8 September 2026, a one-time native appearance diagnostic passed on the iPhone 17 Pro simulator running iOS 27.0 / `24A5423a`, built with Xcode 27 beta 6 / `27A5252f`. The four original full-screen captures were visually inspected. Sayso's complete waveform remains recognizable, centered, and unclipped in each observed style. The actual installed icon is fully visible above the native Customize panel; the generic preview thumbnails inside that panel are not the reviewed artwork.

| Native selection | Observed Sayso icon | Capture |
| --- | --- | --- |
| Default | Purple waveform on a warm white tile | [Default](screenshots/ios27/final-visual/icon-native-default-customize.png) |
| Dark, Always | Pale violet waveform on a black tile | [Dark](screenshots/ios27/final-visual/icon-native-dark-customize.png) |
| Clear, Light | White waveform on the translucent material over the current wallpaper | [Clear](screenshots/ios27/final-visual/icon-native-clear-light-customize.png) |
| Tinted, Light | White waveform on the observed gray material; Use wallpaper color selected, gray gradient value, 100% luma | [Tinted](screenshots/ios27/final-visual/icon-native-tinted-light-wallpaper-gray-customize.png) |

The diagnostic changed only the four top-level appearance choices. Size, wallpaper controls, suboptions, and tint sliders were not activated. It then restored Default and checked the original size/wallpaper control labels, values, and selection state. The [restored icon capture](screenshots/ios27/final-visual/icon-native-default-restored-customize.png) visually matches the initial purple-on-white icon. A separate final capture confirms Customize was dismissed and the original first Home page restored; Sayso is on the second page, so that final image is page-cleanup evidence rather than an unobscured Sayso-icon image.

The [review](../.build/ios27-icon-appearance-visual-review.json) and [image provenance](screenshots/ios27/final-visual/icon-native-appearance-provenance.json) bind the captures to the unchanged icon source hashes above and the diagnostic source hash. Promoted images are byte-identical copies of the attachments. The native diagnostic [log](../.build/test-ios27-icon-appearances-refined.log) and [result bundle](../.build/Sayso-iOS27-Icon-Appearances-Refined.xcresult) record one passing diagnostic method in 52.936 seconds. This opt-in system appearance diagnostic is excluded from the app's unique regression-test count.

Earlier diagnostic failures remain in the review. The first capture-only attempt stopped before a long press because Sayso was offscreen on the first Home page. A later appearance attempt failed an incorrect expectation that the wallpaper action would remain named `Dim wallpaper` under Dark; the native UI changes it to `Brighten wallpaper`. Default and the original controls/page were restored in that failed run. The refined run records the style-dependent action and retains strict final restoration checks.

These captures cover the current small labeled icons, one wallpaper, and the exact suboptions in the table. Other tint colors/luma values, Clear Dark, Tinted Dark, automatic transitions, large icons, continuous icon motion, and physical-device presentation remain unverified. Normal simulator execution succeeded without a security bypass, but the separately documented [runtime signature verification error `-67054`](../.build/ios27-runtime-reimport-review.md) remains unresolved; this visual review does not establish runtime integrity.
