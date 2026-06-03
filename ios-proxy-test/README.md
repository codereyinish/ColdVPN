# iOS Proxy Test

Minimal test app to validate two critical unknowns before building the full proxy.

## What We're Testing

### Test 1 — NWListener
Can an iOS app accept TCP connections from Mac over iPhone hotspot?
- If YES → proxy architecture is viable
- If NO → entire approach fails, need different strategy

### Test 2 — URLSession APN
Does URLSession use phone APN (unlimited) or tethering APN (hotspot cap)?
- If phone APN → AT&T sees it as phone data → bypass works
- If tethering APN → approach doesn't work

## Setup in Xcode

1. Open Xcode → File → New → Project
2. iOS App, Swift, SwiftUI
3. Product Name: `ProxyTest`
4. Save inside this folder
5. Replace generated ContentView.swift with Sources/ContentView.swift
6. Add Sources/TestServer.swift to project
7. In Info.plist add:
   ```xml
   <key>NSLocalNetworkUsageDescription</key>
   <string>Needed to accept connections from Mac over hotspot</string>
   <key>NSBonjourServices</key>
   <array><string>_http._tcp</string></array>
   ```

## Running Tests

### Test 1
1. Tap "Start Listener" in app
2. Connect Mac to iPhone hotspot
3. On Mac: `curl http://172.20.10.1:8080`
4. App should show "✓ Connection received"

### Test 2
1. Connect Mac to iPhone hotspot
2. Text `myatt` to `3282` — screenshot hotspot GB
3. Tap "Run URLSession Test" in app
4. Wait for download to complete
5. Text `myatt` again
6. Compare hotspot GB — unchanged = phone APN ✓
