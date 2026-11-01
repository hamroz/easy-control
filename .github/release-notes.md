## Install

1. Download **EasyControl-*.dmg** below, open it and drag **EasyControl** to **Applications**.
2. Open it once. macOS will say it can't verify the app (it isn't notarized yet, there is no Apple Developer account behind this project). Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/EasyControl.app`
3. Allow **Camera** and **Accessibility** when asked. Look for the hand icon in the menu bar.

Requires macOS 15+ on Apple Silicon. Everything runs on-device; no frames are stored or sent anywhere. Verify the download with the attached `.sha256`.
