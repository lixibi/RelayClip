# RelayClip macOS

This is a standalone macOS 13+ SwiftUI menu bar client for RelayClip Server.

It lives outside the iOS project directory so the original Xcode project and its Git state are untouched.

## Run

```bash
./script/build_and_run.sh
```

The app starts as a menu bar utility. Use the RelayClip item in the macOS menu bar to send the clipboard to the remote server, fetch the latest remote text into the clipboard, quick-copy recent entries, or open the full main window.

## Build Output

The local app bundle is staged at:

```text
dist/RelayClip.app
```
