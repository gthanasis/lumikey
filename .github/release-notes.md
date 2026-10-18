## Install

1. Download **Lumikey-….zip** below and double-click it to unzip.
2. Drag **Lumikey** into your Applications folder and open it.
3. macOS says it can't verify the developer, because the app isn't paid-for signed by Apple. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Lumikey. You only do this once.

If macOS says the app "is damaged", run this in Terminal, then open it again:

```
xattr -dr com.apple.quarantine "/Applications/Lumikey.app"
```

Works on macOS 14 or later, Apple Silicon and Intel. Tested on the Razer Ornata V2; other keyboards are experimental. Use **Test keyboard…** in the app and send the report, so they can be marked as working.
