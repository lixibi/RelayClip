# TextSync iOS

TextSync iOS is a native SwiftUI client for the HEBE TEXT sharing server. It targets iOS 16 and stores the server address locally on device.

## Features

- Fetch and display the latest shared text
- Browse recent history
- Copy the latest or historical text to the clipboard
- Paste from the clipboard and upload new text
- Edit the server address without rebuilding the app

## Server API

The bundled server source lives in `textsync/serversrc`.

- `GET /api/list` returns all entries as JSON
- `GET /api/get` returns the latest text
- `POST /api/post` uploads the request body as a new text entry

## Build IPA on GitHub

Push this repository to GitHub, then run the `Build IPA` workflow from the Actions tab. The generated `.ipa` will be available as a workflow artifact.
