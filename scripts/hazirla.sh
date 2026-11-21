#!/usr/bin/env bash
# Flutter'ın platform klasörlerini oluşturur ve Jarvis'e özel ayarları üstüne yazar.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org com.jarvis --project-name jarvis --platforms android,ios . >/dev/null

# Flutter'ın örnek testini kaldır (bizim uygulamaya uymuyor)
rm -f test/widget_test.dart

# Android: manifest + yerel arka plan servisi
cp -r ek/android/. android/
for f in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$f" ] && sed -i.bak 's/flutter\.minSdkVersion/24/' "$f" && rm -f "$f.bak"
done

# iOS: izin açıklamaları ve en düşük sürüm
python3 - <<'PY'
import plistlib, pathlib
p = pathlib.Path("ios/Runner/Info.plist")
d = plistlib.loads(p.read_bytes())
d["CFBundleDisplayName"] = "Jarvis"
d["NSMicrophoneUsageDescription"] = "Jarvis seni duyabilmek için mikrofonu kullanır."
d["NSSpeechRecognitionUsageDescription"] = "Jarvis söylediklerini anlamak için konuşma tanımayı kullanır."
d["NSContactsUsageDescription"] = "Jarvis kişilerini arayabilmek ve onlara mesaj atabilmek için rehberi kullanır."
d["UIBackgroundModes"] = ["audio"]
d["LSApplicationQueriesSchemes"] = ["tel", "sms", "whatsapp", "spotify", "instagram",
    "youtube", "comgooglemaps", "clock-alarm", "clock-timer", "music"]
p.write_bytes(plistlib.dumps(d))
PY

if [ -f ios/Podfile ]; then
  sed -i.bak "s/^# platform :ios.*/platform :ios, '13.0'/" ios/Podfile && rm -f ios/Podfile.bak
fi

flutter pub get
echo "Hazır."
