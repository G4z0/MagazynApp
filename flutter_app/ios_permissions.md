# Konfiguracja uprawnień iOS

## Info.plist
Dodaj do pliku `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Aplikacja wymaga dostępu do kamery do skanowania kodów kreskowych</string>

<!-- Pozwól na HTTP do serwera lokalnego -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```
