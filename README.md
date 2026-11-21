# J.A.R.V.I.S. — Sesli kişisel asistan (Android + iPhone)

"Jarvis" diye seslen, "Efendim?" desin, isteğini söyle, anında yapsın.

## Neler yapabilir
- Her soruya kısa ve sesli cevap verir (Claude). Hava, haber, kur gibi güncel bilgiler için internette arar.
- "Annemi ara" → rehberden bulup doğrudan arar (Android)
- "Ahmet'e WhatsApp'tan geliyorum yaz" → mesajı hazırlar
- "Yarın 7 buçuğa alarm kur", "10 dakikalık zamanlayıcı" (Android)
- "YouTube'da lo-fi aç", "Spotify'da Tarkan çal", "Kadıköy'e yol tarifi"
- Sana bir soru sorarsa tekrar "Jarvis" demeden cevap verebilirsin
- "Jarvis uyu" → dinlemeyi kapatır

## Sadece telefonla kurulum

### 1. Anahtarları al (bir kerelik)
- **Claude API anahtarı:** console.anthropic.com → kayıt ol → Billing'den bakiye yükle → API Keys → Create Key. (Kullandıkça ücretlendirilir; günlük sohbette genelde birkaç kuruş/cent.)
- **Picovoice AccessKey (ücretsiz):** console.picovoice.ai → kayıt ol → ana sayfadaki AccessKey'i kopyala. "Jarvis" uyandırma kelimesi bununla çalışır.

### 2. Uygulamayı bulutta derlet
1. github.com'da ücretsiz hesap aç.
2. Bu klasördeki dosyaları bir GitHub deposuna (repo) yükle. (Ya da Claude'a deponun adını söyle, o yüklesin.)
3. Depoda **Actions** sekmesine gir → "Jarvis'i derle" otomatik başlar (~10 dk).
4. Bitince deponun **Releases** bölümünde **Jarvis.apk** çıkar.

### 3. Android'e kur
1. Releases'tan **Jarvis.apk**'ya dokun, indir, aç.
2. "Bilinmeyen kaynaklardan yüklemeye izin ver" sorusuna izin ver.
3. Uygulamayı aç → Ayarlar'a iki anahtarı yapıştır → Kaydet.
4. Mikrofon, bildirim, rehber ve telefon izinlerine **İzin ver** de.
5. **Önemli:** Ayarlar → Uygulamalar → Jarvis → Pil → **Kısıtlama yok** seç. Yoksa telefon Jarvis'i arka planda kapatabilir.

### iPhone
Kod iPhone'da da çalışır ama Apple, imzalanmamış uygulama kurulmasına izin vermez. Seçenekler:
- Apple Developer hesabı (yıllık 99$) ile TestFlight üzerinden kurmak, ya da
- Actions'taki "Jarvis-iOS-imzasiz" dosyasını bir bilgisayarla (Sideloadly/AltStore) yüklemek.
iPhone'da Jarvis yalnızca uygulama açıkken "Jarvis" sesini duyar; bu Apple'ın kuralı.

## Sınırlar
- Android'de arka planda dinleme çoğu telefonda çalışır. Ama bazı markalar (özellikle Xiaomi, Huawei) pil ayarları sıkıysa uygulamayı yine kapatabilir.
- Ekran kilitliyken Android, uygulamaların başka uygulama açmasını (YouTube, WhatsApp) engelleyebilir. Jarvis yine cevap verir; açma işlemi telefonu açınca gerçekleşir.
- Konuşma tanıma için telefonda Google (Android) veya Siri dikte (iPhone) etkin olmalı.

## Dosyalar
- `lib/main.dart` — uygulamanın tamamı (uyandırma, dinleme, beyin, eylemler, arayüz)
- `ek/android/...` — Android izinleri ve arka plan dinleme servisi
- `scripts/hazirla.sh` — platform klasörlerini oluşturur
- `.github/workflows/derle.yml` — bulutta derleme
