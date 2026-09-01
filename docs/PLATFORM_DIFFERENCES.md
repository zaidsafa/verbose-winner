# Deliberate iOS platform differences

- Navigation uses native iOS tabs, `NavigationStack`, sheets, swipe actions, grouped forms, and Dynamic Type rather than copying Android bottom-bar or Back behavior.
- The app target deliberately requires iOS 26.1 so it can use the current native Liquid Glass design and tab-bar bottom accessory directly. Navigation and controls use system-provided glass; custom glass is reserved for important interactive surfaces and grouped in shared effect containers.
- The initial visual identity is Paper glass: warm paper content, ink typography, and native Liquid Glass controls. It does not claim to reproduce Android's custom Glass renderer pixel-for-pixel.
- SwiftData is the offline local store on iOS; Android Room remains Android-only. Backup records provide the cross-platform interchange boundary.
- Receipt import uses system PhotosPicker without broad photo-library permission. Notification authorization is requested only when the user explicitly saves an expense with a reminder.
- App signing, Google OAuth configuration, TestFlight, and App Store settings are intentionally outside this repository milestone and require explicit approval.
