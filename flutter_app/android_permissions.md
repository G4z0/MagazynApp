# Konfiguracja uprawnień Android

## AndroidManifest.xml
Dodaj te uprawnienia do pliku `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Uprawnienie do kamery (skanowanie kodów) -->
    <uses-permission android:name="android.permission.CAMERA" />

    <!-- Uprawnienie do internetu (połączenie z API) -->
    <uses-permission android:name="android.permission.INTERNET" />

    <!-- WAŻNE: Pozwól na ruch HTTP (nie HTTPS) do serwera lokalnego -->
    <application
        android:usesCleartextTraffic="true"
        ...>
```

## WAŻNE: android:usesCleartextTraffic
Ponieważ serwer 192.168.1.42 używa HTTP (nie HTTPS), musisz dodać
`android:usesCleartextTraffic="true"` w tagu `<application>`.
Bez tego Android zablokuje połączenia HTTP.
