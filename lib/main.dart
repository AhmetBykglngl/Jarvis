import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:porcupine_flutter/porcupine.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisApp());
}

const Color kMavi = Color(0xFF3FD0FF);
const Color kKoyu = Color(0xFF05080F);

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jarvis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kKoyu,
        colorScheme: const ColorScheme.dark(primary: kMavi, secondary: kMavi),
        useMaterial3: true,
      ),
      home: const JarvisEkrani(),
    );
  }
}

// ---------------------------------------------------------------------------
// Ayarlar
// ---------------------------------------------------------------------------

class Ayarlar {
  String claudeAnahtar = '';
  String picovoiceAnahtar = '';
  String model = 'claude-sonnet-5-5';
  String isim = '';
  double hassasiyet = 0.65;
  bool arkaPlan = true;
  bool webArama = true;

  static Future<Ayarlar> yukle() async {
    final p = await SharedPreferences.getInstance();
    return Ayarlar()
      ..claudeAnahtar = p.getString('claude') ?? ''
      ..picovoiceAnahtar = p.getString('picovoice') ?? ''
      ..model = p.getString('model') ?? 'claude-sonnet-5-5'
      ..isim = p.getString('isim') ?? ''
      ..hassasiyet = p.getDouble('hassasiyet') ?? 0.65
      ..arkaPlan = p.getBool('arkaPlan') ?? true
      ..webArama = p.getBool('webArama') ?? true;
  }

  Future<void> kaydet() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('claude', claudeAnahtar.trim());
    await p.setString('picovoice', picovoiceAnahtar.trim());
    await p.setString('model', model.trim());
    await p.setString('isim', isim.trim());
    await p.setDouble('hassasiyet', hassasiyet);
    await p.setBool('arkaPlan', arkaPlan);
    await p.setBool('webArama', webArama);
  }

  bool get hazir => claudeAnahtar.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Beyin: Claude API
// ---------------------------------------------------------------------------

class Cevap {
  final String soz;
  final Map<String, dynamic>? eylem;
  final bool dinlemeyeDevam;
  Cevap(this.soz, this.eylem, this.dinlemeyeDevam);
}

class Beyin {
  final List<Map<String, dynamic>> _gecmis = [];

  String _sistem(Ayarlar a) {
    final simdi = DateTime.now();
    final tarih =
        '${simdi.day}.${simdi.month}.${simdi.year} ${simdi.hour.toString().padLeft(2, '0')}:${simdi.minute.toString().padLeft(2, '0')}';
    final platform = Platform.isIOS ? 'iPhone (iOS)' : 'Android';
    final kim = a.isim.isEmpty ? 'kullanıcının' : '${a.isim} adlı kullanıcının';
    return '''
Sen Jarvis'sin, $kim kişisel yapay zekâ asistanı. Iron Man'deki J.A.R.V.I.S. gibisin: sadık, zeki, sakin, hafif esprili.

DAVRANIŞ:
- İstenen şeyi hemen yap. Sorgulama, ders verme, uyarı ekleme, "emin misiniz" deme, gereksiz soru sorma.
- Eksik bilgi varsa en makul varsayımı yap ve uygula. Yalnızca gerçekten imkânsızsa tek kısa soru sor.
- Cevapların sesli okunacak: en fazla 1-2 kısa cümle. Markdown, emoji, madde işareti, link yazma.
- Kullanıcıya "efendim" diye hitap et. Türkçe konuş (kullanıcı başka dilde konuşursa o dilde).
- Güncel bilgi (hava, haber, kur, maç, fiyat vb.) gerekiyorsa web_search aracını kullan.

ŞU AN: $tarih. CİHAZ: $platform.

ÇIKTI: Cevabını SADECE tek bir JSON nesnesi olarak ver, başka hiçbir şey yazma:
{"soz": "sesli söylenecek cümle", "eylem": null, "dinlemeye_devam": false}

"dinlemeye_devam": Kullanıcıya soru sorduysan true yap (tekrar "Jarvis" demeden cevap verebilsin).

"eylem" şunlardan biri olabilir:
1) Telefonla arama: {"tur": "ara", "kisi": "Annem"} veya {"tur": "ara", "numara": "05551234567"}
2) Mesaj: {"tur": "mesaj", "kisi": "Ahmet", "metin": "Geliyorum", "uygulama": "whatsapp"}  (uygulama: "sms" veya "whatsapp"; kisi yerine "numara" da olabilir)
3) Alarm: {"tur": "alarm", "saat": 7, "dakika": 30, "etiket": "Uyan"}
4) Zamanlayıcı: {"tur": "zamanlayici", "saniye": 300, "etiket": "Çay"}
5) Uygulama/site/harita/müzik/video açma: {"tur": "link", "url": "..."}
   Örnekler: "https://www.youtube.com/results?search_query=..." , "spotify:search:...",
   "https://www.google.com/maps/dir/?api=1&destination=..." , "https://www.google.com/search?q=...",
   "whatsapp://", "instagram://", "https://...". Uygun URL şemasını kendin seç.
6) Dinlemeyi tamamen kapat: {"tur": "uyku"}
''';
  }

  void sifirla() => _gecmis.clear();

  Future<Cevap> sor(String metin, Ayarlar a) async {
    _gecmis.add({'role': 'user', 'content': metin});
    while (_gecmis.length > 20) {
      _gecmis.removeAt(0);
    }
    while (_gecmis.isNotEmpty && _gecmis.first['role'] != 'user') {
      _gecmis.removeAt(0);
    }

    final govde = <String, dynamic>{
      'model': a.model,
      'max_tokens': 1024,
      'system': _sistem(a),
      'messages': _gecmis,
    };
    if (a.webArama) {
      govde['tools'] = [
        {'type': 'web_search_20250305', 'name': 'web_search', 'max_uses': 3}
      ];
    }

    final yanit = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'content-type': 'application/json',
            'x-api-key': a.claudeAnahtar,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode(govde),
        )
        .timeout(const Duration(seconds: 60));

    if (yanit.statusCode != 200) {
      _gecmis.removeLast();
      String detay = yanit.body;
      try {
        detay = jsonDecode(yanit.body)['error']['message'] ?? detay;
      } catch (_) {}
      if (yanit.statusCode == 401) {
        throw Exception('Claude anahtarı geçersiz. Ayarlardan kontrol edin.');
      }
      throw Exception('Claude hatası (${yanit.statusCode}): $detay');
    }

    final veri = jsonDecode(utf8.decode(yanit.bodyBytes));
    final buf = StringBuffer();
    for (final blok in (veri['content'] as List)) {
      if (blok['type'] == 'text') buf.write(blok['text']);
    }
    final ham = buf.toString().trim();
    final cevap = _coz(ham);
    _gecmis.add({
      'role': 'assistant',
      'content': ham.isEmpty ? '{"soz": "", "eylem": null}' : ham
    });
    return cevap;
  }

  Cevap _coz(String ham) {
    final bas = ham.indexOf('{');
    final son = ham.lastIndexOf('}');
    if (bas != -1 && son > bas) {
      try {
        final j = jsonDecode(ham.substring(bas, son + 1));
        if (j is Map<String, dynamic>) {
          final eylem = j['eylem'];
          return Cevap(
            (j['soz'] ?? '').toString(),
            eylem is Map<String, dynamic> ? eylem : null,
            j['dinlemeye_devam'] == true,
          );
        }
      } catch (_) {}
    }
    return Cevap(ham.replaceAll(RegExp(r'[*#`_]'), ''), null, false);
  }
}

// ---------------------------------------------------------------------------
// Eylemler
// ---------------------------------------------------------------------------

class Eylemler {
  static String kucukHarf(String s) => _kucuk(s);

  static String _kucuk(String s) => s
      .replaceAll('I', 'ı')
      .replaceAll('İ', 'i')
      .toLowerCase()
      .trim();

  static Future<String?> _numaraBul(Map<String, dynamic> e) async {
    final numara = (e['numara'] ?? '').toString().trim();
    if (numara.isNotEmpty) return numara;
    final kisi = (e['kisi'] ?? '').toString().trim();
    if (kisi.isEmpty) return null;
    if (!await FlutterContacts.requestPermission(readonly: true)) return null;
    final rehber = await FlutterContacts.getContacts(withProperties: true);
    final aranan = _kucuk(kisi);
    Contact? bulunan;
    for (final c in rehber) {
      if (c.phones.isEmpty) continue;
      if (_kucuk(c.displayName) == aranan) {
        bulunan = c;
        break;
      }
    }
    bulunan ??= rehber.cast<Contact?>().firstWhere(
          (c) => c!.phones.isNotEmpty && _kucuk(c.displayName).contains(aranan),
          orElse: () => null,
        );
    bulunan ??= rehber.cast<Contact?>().firstWhere(
          (c) =>
              c!.phones.isNotEmpty &&
              aranan.split(' ').every((p) => _kucuk(c.displayName).contains(p)),
          orElse: () => null,
        );
    return bulunan?.phones.first.number;
  }

  static String _uluslararasi(String n) {
    var d = n.replaceAll(RegExp(r'[^0-9+]'), '');
    if (d.startsWith('+')) return d.substring(1);
    if (d.startsWith('00')) return d.substring(2);
    if (d.startsWith('0')) return '90${d.substring(1)}';
    if (d.length == 10 && d.startsWith('5')) return '90$d';
    return d;
  }

  static Future<bool> _ac(String url) async {
    try {
      return await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Eylemi uygular. Sorun olursa söylenecek bir cümle döner, yoksa null.
  static Future<String?> uygula(Map<String, dynamic> e) async {
    final tur = (e['tur'] ?? '').toString();
    switch (tur) {
      case 'ara':
        final n = await _numaraBul(e);
        if (n == null) return 'Bu kişiyi rehberinizde bulamadım efendim.';
        if (Platform.isAndroid &&
            await Permission.phone.request().isGranted) {
          await AndroidIntent(
                  action: 'android.intent.action.CALL', data: 'tel:$n')
              .launch();
          return null;
        }
        await _ac('tel:${n.replaceAll(' ', '')}');
        return null;

      case 'mesaj':
        final n = await _numaraBul(e);
        if (n == null) return 'Bu kişiyi rehberinizde bulamadım efendim.';
        final metin = (e['metin'] ?? '').toString();
        if ((e['uygulama'] ?? 'sms') == 'whatsapp') {
          final ok = await _ac(
              'https://wa.me/${_uluslararasi(n)}?text=${Uri.encodeComponent(metin)}');
          if (!ok) return 'WhatsApp açılamadı efendim.';
        } else {
          final ayrac = Platform.isIOS ? '&' : '?';
          await _ac(
              'sms:${n.replaceAll(' ', '')}${ayrac}body=${Uri.encodeComponent(metin)}');
        }
        return null;

      case 'alarm':
        final saat = (e['saat'] as num?)?.toInt() ?? 7;
        final dakika = (e['dakika'] as num?)?.toInt() ?? 0;
        if (Platform.isAndroid) {
          await AndroidIntent(
            action: 'android.intent.action.SET_ALARM',
            arguments: <String, dynamic>{
              'android.intent.extra.alarm.HOUR': saat,
              'android.intent.extra.alarm.MINUTES': dakika,
              'android.intent.extra.alarm.MESSAGE':
                  (e['etiket'] ?? 'Jarvis').toString(),
              'android.intent.extra.alarm.SKIP_UI': true,
            },
          ).launch();
          return null;
        }
        await _ac('clock-alarm://');
        return 'iPhone alarmı doğrudan kurmama izin vermiyor, Saat uygulamasını açtım efendim.';

      case 'zamanlayici':
        final sn = (e['saniye'] as num?)?.toInt() ?? 60;
        if (Platform.isAndroid) {
          await AndroidIntent(
            action: 'android.intent.action.SET_TIMER',
            arguments: <String, dynamic>{
              'android.intent.extra.alarm.LENGTH': sn,
              'android.intent.extra.alarm.MESSAGE':
                  (e['etiket'] ?? 'Jarvis').toString(),
              'android.intent.extra.alarm.SKIP_UI': true,
            },
          ).launch();
          return null;
        }
        await _ac('clock-timer://');
        return 'iPhone zamanlayıcıyı doğrudan kurmama izin vermiyor, Saat uygulamasını açtım efendim.';

      case 'link':
        final url = (e['url'] ?? '').toString();
        if (url.isEmpty) return null;
        if (!await _ac(url)) {
          // Uygulama yoksa web'de aramayı dene
          final ok = await _ac(
              'https://www.google.com/search?q=${Uri.encodeComponent(url)}');
          if (!ok) return 'Bunu açamadım efendim.';
        }
        return null;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Ana ekran
// ---------------------------------------------------------------------------

enum Durum { kapali, bekliyor, dinliyor, dusunuyor, konusuyor }

class Mesaj {
  final bool benden;
  final String metin;
  Mesaj(this.benden, this.metin);
}

class JarvisEkrani extends StatefulWidget {
  const JarvisEkrani({super.key});

  @override
  State<JarvisEkrani> createState() => _JarvisEkraniState();
}

class _JarvisEkraniState extends State<JarvisEkrani>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _kanal = MethodChannel('jarvis/arkaplan');

  Ayarlar _ayar = Ayarlar();
  final Beyin _beyin = Beyin();
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  PorcupineManager? _porcupine;

  Durum _durum = Durum.kapali;
  String _canli = '';
  String _hata = '';
  bool _sttHazir = false;
  bool _islemde = false;
  final List<Mesaj> _mesajlar = [];
  final TextEditingController _yazi = TextEditingController();
  final ScrollController _kaydir = ScrollController();
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anim = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _baslat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _anim.dispose();
    _porcupine?.delete();
    _stt.cancel();
    _tts.stop();
    super.dispose();
  }

  Future<void> _baslat() async {
    _ayar = await Ayarlar.yukle();
    await _ttsKur();
    if (Platform.isAndroid) {
      await Permission.microphone.request();
      await Permission.notification.request();
    }
    _sttHazir = await _stt.initialize(
      onError: (e) {
        if (_durum == Durum.dinliyor) _dinlemeBitti('');
        if (_durum == Durum.bekliyor && _porcupine == null) {
          _uyanikYenile(_dongu);
        }
      },
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') &&
            _durum == Durum.bekliyor &&
            _porcupine == null &&
            !_islemde) {
          _uyanikYenile(_dongu);
        }
      },
    );
    if (!_ayar.hazir) {
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _ayarlariAc());
      return;
    }
    await _uyandirmaKur();
  }

  Future<void> _ttsKur() async {
    await _tts.awaitSpeakCompletion(true);
    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playAndRecord,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
    await _tts.setLanguage('tr-TR');
    await _tts.setSpeechRate(Platform.isIOS ? 0.52 : 0.55);
    await _tts.setPitch(0.9);
  }

  Future<void> _uyandirmaKur() async {
    await _porcupine?.delete();
    _porcupine = null;
    if (_ayar.picovoiceAnahtar.isEmpty) {
      // Anahtarsız mod: telefonun konuşma tanımasıyla "Jarvis"i yakala
      await _bekle();
      if (Platform.isAndroid && _ayar.arkaPlan) {
        await _kanal.invokeMethod('baslat');
      }
      return;
    }
    try {
      _porcupine = await PorcupineManager.fromBuiltInKeywords(
        _ayar.picovoiceAnahtar,
        [BuiltInKeyword.JARVIS],
        _uyandi,
        sensitivities: [_ayar.hassasiyet],
        errorCallback: (PorcupineException e) =>
            _hataGoster('Uyandırma motoru: ${e.message}'),
      );
      await _bekle();
      if (Platform.isAndroid && _ayar.arkaPlan) {
        await _kanal.invokeMethod('baslat');
      }
    } on PorcupineException catch (e) {
      _hataGoster(
          'Picovoice anahtarı çalışmadı (${e.message}). Anahtarsız modda devam ediliyor.');
      _porcupine = null;
      await _bekle();
    }
  }

  Future<void> _bekle() async {
    _canli = '';
    if (_porcupine == null) {
      if (mounted) setState(() => _durum = Durum.bekliyor);
      _uyanikDinle();
      return;
    }
    try {
      await _porcupine?.start();
      if (mounted) setState(() => _durum = Durum.bekliyor);
    } on PorcupineException catch (e) {
      _hataGoster('Mikrofon açılamadı: ${e.message}');
      if (mounted) setState(() => _durum = Durum.kapali);
    }
  }

  // ---- Anahtarsız uyandırma: sürekli dinle, "Jarvis" geçince uyan ----
  int _dongu = 0;
  static final RegExp _uyanmaKalibi = RegExp(
      r'(jarvis|jarvıs|carvis|carvıs|cervis|çarvis|çervis|jarviz|carviz|jervis|jarbis|zarvis|şarvis)');

  Future<void> _uyanikDinle() async {
    if (_durum != Durum.bekliyor || _islemde || !_sttHazir) return;
    final benim = ++_dongu;
    if (_stt.isListening) await _stt.cancel();
    if (benim != _dongu) return;
    try {
      await _stt.listen(
        localeId: 'tr_TR',
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(milliseconds: 1500),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
        onResult: (SpeechRecognitionResult r) {
          if (benim != _dongu || _durum != Durum.bekliyor) return;
          final kucuk = Eylemler.kucukHarf(r.recognizedWords);
          final m = _uyanmaKalibi.firstMatch(kucuk);
          if (m == null) {
            if (r.finalResult) _uyanikYenile(benim);
            return;
          }
          if (!r.finalResult) {
            setState(() => _canli = r.recognizedWords);
            return;
          }
          _dongu++;
          final kalan = kucuk
              .substring(m.end)
              .replaceFirst(RegExp(r'^[\s,.!?]+'), '')
              .trim();
          _sesliUyandi(kalan);
        },
      );
    } catch (_) {
      _uyanikYenile(benim);
    }
  }

  void _uyanikYenile(int benim) {
    if (benim != _dongu) return;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (benim == _dongu &&
          _durum == Durum.bekliyor &&
          _porcupine == null &&
          !_islemde) {
        _uyanikDinle();
      }
    });
  }

  Future<void> _sesliUyandi(String kalan) async {
    HapticFeedback.mediumImpact();
    if (kalan.split(' ').where((k) => k.isNotEmpty).length >= 2) {
      // "Jarvis, hava nasıl" gibi tek seferde söylendiyse direkt yap
      await _isle(kalan);
      return;
    }
    await _konus('Efendim?');
    await _dinle();
  }

  void _hataGoster(String m) {
    if (!mounted) return;
    setState(() => _hata = m);
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted && _hata == m) setState(() => _hata = '');
    });
  }

  // "Jarvis" duyuldu
  Future<void> _uyandi(int _) async {
    if (_islemde) return;
    HapticFeedback.mediumImpact();
    await _porcupine?.stop();
    await _konus('Efendim?');
    await _dinle();
  }

  Future<void> _dinle() async {
    if (!_sttHazir) {
      _hataGoster('Konuşma tanıma bu cihazda kullanılamıyor.');
      await _bekle();
      return;
    }
    await _porcupine?.stop();
    _dongu++;
    if (_stt.isListening) await _stt.cancel();
    setState(() {
      _durum = Durum.dinliyor;
      _canli = '';
    });
    await Future.delayed(const Duration(milliseconds: 150));
    await _stt.listen(
      localeId: 'tr_TR',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(milliseconds: 1800),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
      onResult: (SpeechRecognitionResult r) {
        setState(() => _canli = r.recognizedWords);
        if (r.finalResult) _dinlemeBitti(r.recognizedWords);
      },
    );
    // Hiç ses gelmezse güvenlik zamanlayıcısı
    Future.delayed(const Duration(seconds: 9), () {
      if (_durum == Durum.dinliyor && _canli.isEmpty && !_islemde) {
        _stt.stop();
        _dinlemeBitti('');
      }
    });
  }

  Future<void> _dinlemeBitti(String metin) async {
    if (_durum != Durum.dinliyor) return;
    metin = metin.trim();
    if (metin.isEmpty) {
      await _bekle();
      return;
    }
    await _isle(metin);
  }

  Future<void> _isle(String metin) async {
    if (_islemde) return;
    _islemde = true;
    _dongu++;
    if (_stt.isListening) await _stt.cancel();
    await _porcupine?.stop();
    setState(() {
      _durum = Durum.dusunuyor;
      _canli = '';
      _mesajlar.add(Mesaj(true, metin));
    });
    _asagiKaydir();

    bool tekrarDinle = false;
    try {
      final c = await _beyin.sor(metin, _ayar);
      if (c.soz.isNotEmpty) {
        setState(() => _mesajlar.add(Mesaj(false, c.soz)));
        _asagiKaydir();
      }
      if (c.eylem != null && c.eylem!['tur'] == 'uyku') {
        await _konus(c.soz);
        _islemde = false;
        await _kapat();
        return;
      }
      // Eylemi konuşmayla aynı anda başlat: anında tepki
      final eylemIs =
          c.eylem != null ? Eylemler.uygula(c.eylem!) : Future.value(null);
      await _konus(c.soz);
      final sorun = await eylemIs;
      if (sorun != null) {
        setState(() => _mesajlar.add(Mesaj(false, sorun)));
        await _konus(sorun);
      }
      tekrarDinle = c.dinlemeyeDevam;
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '');
      final sesli = m.contains('SocketException') || m.contains('Timeout')
          ? 'İnternet bağlantısında sorun var efendim.'
          : 'Bir sorun oluştu efendim.';
      setState(() => _mesajlar.add(Mesaj(false, '$sesli\n($m)')));
      await _konus(sesli);
    }
    _islemde = false;
    if (tekrarDinle) {
      await _dinle();
    } else {
      await _bekle();
    }
  }

  Future<void> _konus(String metin) async {
    if (metin.trim().isEmpty) return;
    if (mounted) setState(() => _durum = Durum.konusuyor);
    await _tts.speak(metin);
  }

  Future<void> _kapat() async {
    _dongu++;
    if (mounted) setState(() => _durum = Durum.kapali);
    await _porcupine?.stop();
    await _stt.cancel();
    await _tts.stop();
    if (Platform.isAndroid) await _kanal.invokeMethod('durdur');
    if (mounted) setState(() => _durum = Durum.kapali);
  }

  Future<void> _merkezeDokun() async {
    switch (_durum) {
      case Durum.kapali:
        if (!_ayar.hazir) return _ayarlariAc();
        if (_porcupine == null) {
          await _uyandirmaKur();
        } else {
          await _bekle();
          if (Platform.isAndroid && _ayar.arkaPlan) {
            await _kanal.invokeMethod('baslat');
          }
        }
        break;
      case Durum.bekliyor:
        await _dinle();
        break;
      case Durum.dinliyor:
        await _stt.stop();
        break;
      case Durum.konusuyor:
        await _tts.stop();
        break;
      case Durum.dusunuyor:
        break;
    }
  }

  void _yaziGonder() {
    final t = _yazi.text.trim();
    if (t.isEmpty || _islemde) return;
    _yazi.clear();
    FocusScope.of(context).unfocus();
    if (_durum == Durum.dinliyor) _stt.cancel();
    _isle(t);
  }

  void _asagiKaydir() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_kaydir.hasClients) {
        _kaydir.animateTo(_kaydir.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _ayarlariAc() async {
    final degisti = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AyarlarEkrani(ayar: _ayar)),
    );
    if (degisti == true) {
      _ayar = await Ayarlar.yukle();
      if (_ayar.hazir) await _uyandirmaKur();
    }
  }

  String get _durumYazisi {
    switch (_durum) {
      case Durum.kapali:
        return _ayar.hazir ? 'Kapalı · başlatmak için dokun' : 'Ayarları yap';
      case Durum.bekliyor:
        return '"Jarvis" de · ya da dokun';
      case Durum.dinliyor:
        return 'Dinliyorum...';
      case Durum.dusunuyor:
        return 'Düşünüyorum...';
      case Durum.konusuyor:
        return 'Konuşuyor · susturmak için dokun';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  const Text('J.A.R.V.I.S.',
                      style: TextStyle(
                          color: kMavi,
                          fontSize: 18,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Sohbeti temizle',
                    icon: const Icon(Icons.refresh, color: Colors.white54),
                    onPressed: () => setState(() {
                      _beyin.sifirla();
                      _mesajlar.clear();
                    }),
                  ),
                  IconButton(
                    tooltip: _durum == Durum.kapali ? 'Başlat' : 'Kapat',
                    icon: Icon(
                        _durum == Durum.kapali
                            ? Icons.power_settings_new
                            : Icons.power_off,
                        color: Colors.white54),
                    onPressed: () => _durum == Durum.kapali
                        ? _merkezeDokun()
                        : _kapat(),
                  ),
                  IconButton(
                    tooltip: 'Ayarlar',
                    icon: const Icon(Icons.settings, color: Colors.white54),
                    onPressed: _ayarlariAc,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _merkezeDokun,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => CustomPaint(
                  size: const Size(220, 220),
                  painter: ReaktorCizici(_anim.value, _durum),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(_durumYazisi,
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
            if (_canli.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(_canli,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kMavi, fontSize: 17)),
              ),
            if (_hata.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(_hata,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13)),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: _kaydir,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _mesajlar.length,
                itemBuilder: (_, i) {
                  final m = _mesajlar[i];
                  return Align(
                    alignment:
                        m.benden ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.8),
                      decoration: BoxDecoration(
                        color: m.benden
                            ? kMavi.withOpacity(0.18)
                            : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: m.benden
                                ? kMavi.withOpacity(0.4)
                                : Colors.white12),
                      ),
                      child: Text(m.metin,
                          style: const TextStyle(fontSize: 15, height: 1.3)),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _yazi,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _yaziGonder(),
                      decoration: InputDecoration(
                        hintText: 'Yaz ya da "Jarvis" de...',
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _yaziGonder,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReaktorCizici extends CustomPainter {
  final double t;
  final Durum durum;
  ReaktorCizici(this.t, this.durum);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final aktif = durum != Durum.kapali;
    final renk = durum == Durum.dinliyor
        ? const Color(0xFF6BFFB8)
        : durum == Durum.dusunuyor
            ? const Color(0xFFFFC857)
            : kMavi;
    final nabiz = durum == Durum.konusuyor || durum == Durum.dinliyor
        ? 0.5 + 0.5 * math.sin(t * math.pi * 8)
        : 0.5 + 0.5 * math.sin(t * math.pi * 2);
    final opak = aktif ? 1.0 : 0.25;

    // Parıltı
    canvas.drawCircle(
      c,
      r * 0.55,
      Paint()
        ..color = renk.withOpacity((0.25 + 0.25 * nabiz) * opak)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
    );

    // Dış halkalar
    final halka = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = renk.withOpacity(0.5 * opak);
    canvas.drawCircle(c, r * 0.95, halka);
    canvas.drawCircle(c, r * 0.78, halka..strokeWidth = 1);

    // Dönen yaylar
    final yay = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = renk.withOpacity(0.9 * opak);
    final hiz = durum == Durum.dusunuyor ? 3.0 : 1.0;
    for (int i = 0; i < 3; i++) {
      final bas = t * 2 * math.pi * hiz + i * 2 * math.pi / 3;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.87), bas, 1.2,
          false, yay);
    }
    final yay2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = renk.withOpacity(0.7 * opak);
    for (int i = 0; i < 6; i++) {
      final bas = -t * 2 * math.pi * hiz + i * math.pi / 3;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.68), bas, 0.6,
          false, yay2);
    }

    // Çekirdek
    canvas.drawCircle(
      c,
      r * (0.32 + 0.04 * nabiz),
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withOpacity(opak),
          renk.withOpacity(0.9 * opak),
          renk.withOpacity(0.0),
        ], stops: const [0.0, 0.45, 1.0])
            .createShader(Rect.fromCircle(center: c, radius: r * 0.4)),
    );
  }

  @override
  bool shouldRepaint(covariant ReaktorCizici o) => true;
}

// ---------------------------------------------------------------------------
// Ayarlar ekranı
// ---------------------------------------------------------------------------

class AyarlarEkrani extends StatefulWidget {
  final Ayarlar ayar;
  const AyarlarEkrani({super.key, required this.ayar});

  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  late final TextEditingController _claude =
      TextEditingController(text: widget.ayar.claudeAnahtar);
  late final TextEditingController _pico =
      TextEditingController(text: widget.ayar.picovoiceAnahtar);
  late final TextEditingController _model =
      TextEditingController(text: widget.ayar.model);
  late final TextEditingController _isim =
      TextEditingController(text: widget.ayar.isim);
  late double _hassasiyet = widget.ayar.hassasiyet;
  late bool _arkaPlan = widget.ayar.arkaPlan;
  late bool _webArama = widget.ayar.webArama;

  Future<void> _kaydet() async {
    widget.ayar
      ..claudeAnahtar = _claude.text
      ..picovoiceAnahtar = _pico.text
      ..model = _model.text.isEmpty ? 'claude-sonnet-5-5' : _model.text
      ..isim = _isim.text
      ..hassasiyet = _hassasiyet
      ..arkaPlan = _arkaPlan
      ..webArama = _webArama;
    await widget.ayar.kaydet();
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _alan(String etiket, TextEditingController c,
      {String? ipucu, bool gizli = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: c,
        obscureText: gizli,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: etiket,
          helperText: ipucu,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _alan('Claude API anahtarı', _claude,
              gizli: true,
              ipucu: 'console.anthropic.com → API Keys (sk-ant-... ile başlar)'),
          _alan('Picovoice AccessKey (isteğe bağlı)', _pico,
              gizli: true,
              ipucu:
                  'İsteğe bağlı. Boş bırakırsan Jarvis telefonun kendi konuşma tanımasıyla uyanır. Varsa daha hızlı ve pil dostu çalışır.'),
          _alan('Adın (isteğe bağlı)', _isim,
              ipucu: 'Jarvis sana adınla hitap edebilsin'),
          _alan('Model', _model, ipucu: 'Varsayılan: claude-sonnet-5-5'),
          const SizedBox(height: 8),
          Text('"Jarvis" duyarlılığı: ${(_hassasiyet * 100).round()}%'),
          Slider(
            value: _hassasiyet,
            min: 0.3,
            max: 0.95,
            onChanged: (v) => setState(() => _hassasiyet = v),
          ),
          const Text(
            'Yüksek: daha kolay uyanır ama yanlışlıkla uyanabilir. Düşük: daha seçici.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('İnternette arama'),
            subtitle: const Text('Hava, haber, kur gibi güncel sorular için'),
            value: _webArama,
            onChanged: (v) => setState(() => _webArama = v),
          ),
          if (Platform.isAndroid)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Arka planda dinle'),
              subtitle: const Text(
                  'Uygulama kapalıyken de "Jarvis" dediğinde uyanır (bildirimde görünür)'),
              value: _arkaPlan,
              onChanged: (v) => setState(() => _arkaPlan = v),
            ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _kaydet, child: const Text('Kaydet')),
        ],
      ),
    );
  }
}
