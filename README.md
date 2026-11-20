<p align="center">
  <img src="assets/titiz-logo.png" alt="Titiz Logo" width="156" />
</p>

# Titiz

> **English Overview:** **Titiz** is an open-source, 100% offline, deterministic macOS menu bar utility built for people who write Turkish on an English keyboard. It restores missing Turkish diacritics (`ç, ğ, ı, İ, ö, ş, ü`) and fixes high-confidence Turkish spelling and punctuation mistakes locally with zero cloud calls, zero API keys, and zero generative rewriting. Titiz prioritizes **precision strictly over recall** ("never break what is already correct"), protecting proper nouns, brand names, code identifiers, and English technical terms out of the box.

---

## Uygulama Amacı

**Titiz**, İngilizce (QWERTY) klavyeyle Türkçe yazarken eksik kalan Türkçe karakterleri (`ç, ğ, ı, İ, ö, ş, ü`) ve sık yapılan açık yazım/noktalama hatalarını **tamamen çevrimdışı**, **deterministik** ve **milisaniyeler içinde** düzelten yerel bir macOS menü çubuğu uygulamasıdır.

Menü çubuğundan açıp metni yapıştırın (`⌘V`), **"Düzelt"** (`⌘↩`) düğmesine basın ve sonucu kopyalayın (`⌘⇧C`):

- **Örnek:**
  - **Girdi:** `Dune Part Three 18 Aralik'ta cikiyor ama ayni gun gitsem mi bilemedim ne dersin?`
  - **Çıktı:** `Dune Part Three 18 Aralık'ta çıkıyor ama aynı gün gitsem mi bilemedim ne dersin?`
  - *(`Dune Part Three` film başlığı ve `18` korunur; `Aralik'ta → Aralık'ta`, `cikiyor → çıkıyor`, `ayni → aynı` ve bağlama bağlı `gun → gün` düzeltilir, doğru yazılmış `gitsem mi` olduğu gibi bırakılır.)*

---

## Neden Titiz?

Metni baştan yazan veya internete gönderen üretken yapay zeka araçlarının ve katı sözlük denetleyicilerinin aksine Titiz, gündelik teknik/profesyonel Türkçe yazımı için tasarlanmıştır:

- **"Doğru Olanı Bozmama" Garantisi:** Hassasiyeti (precision) her zaman kapsamın (recall) önünde tutar. Belirsiz sözcüklerde tahmin yürütmez; özgün hâlini korur ve olası alternatifleri tıklanabilir öneri olarak sunar. Üsluba, kip veya cümle yapısına asla müdahale etmez (`Gönder` hiçbir zaman `gönderin` yapılmaz).
- **%100 Çevrimdışı ve Anlık Hız:** Hesap, API anahtarı, telemetri veya bulut çağrısı yoktur. Tüm metinler yalnızca kendi Mac'inizde işlenir (kısa metinlerde **< 1 ms**, uzun metinlerde **~7 ms**). İsteğe bağlı sürüm kontrolü yalnızca Ayarlar içindeki **"Güncellemeleri Denetle"** düğmesine bastığınızda GitHub Releases üzerinden yapılır.
- **4 Katmanlı Akıllı Koruma:** URL'ler, dosya yolları, kod tanımlayıcıları (`TitizNSTextView`, `MaviKutu`), kısaltmalar (`API'ye`, `JSON`), İngilizce teknik terimler (`driver`, `container`, `"Check for Updates"`), marka/özel adlar (`Intel`, `Netflix`, `Can Bey`) ve yabancı köke gelen Türkçe ekler (`Apple'da`, `Docker'dan`, `GitHub'ta`) otomatik korunur; Türkçe özel adlar ise (`Istanbul'dan → İstanbul'dan`, `Aralik'ta → Aralık'ta`) güvenle onarılır.
- **Kişisel Sözlük ("Bu adı hep koru"):** Herhangi bir marka, ürün veya proje adını (`Yeni Proje X`, `MaviKutu`) seçip **"Bu adı hep koru"** diyerek anında en yüksek öncelikli koruma katmanına ekleyebilirsiniz.
- **Şeffaf TDK Gerekçesi ve Bağımsız Geri Al:** Düzenlenen her sözcüğe tıklayarak uygulanan TDK/karakter kuralını ve açıklamasını görebilir, tek tıkla **"Geri Al"** diyebilir veya son 5 düzeltmenize yerel geçmişten ulaşabilirsiniz.
- **Saf Yerel macOS Deneyimi:** Electron veya tarayıcı tabanlı ağır çerçeveler yerine Swift, AppKit ve SwiftUI (`macOS 26+` için Liquid Glass) ile yazılmıştır; menü çubuğunda hafifçe ve sessizce çalışır.

---

## Çalışma Modları

1. **`Karakter`:**
   - Yalnızca ASCII harflerden (`c, g, i, o, s, u`) eksik Türkçe karakterleri (`ç, ğ, ı, İ, ö, ş, ü`) **tek yönlü** olarak tamamlar (`yarin disari cikacagim → yarın dışarı çıkacağım`).
   - Metinde zaten bulunan Türkçe karakterleri bozmaz; büyük/küçük harf, noktalama veya sözcük ayırma yapmaz.
2. **`Yazım`:**
   - Yüksek güvenli TDK yazım ve noktalama kurallarını uygular: noktalama boşlukları (`? ! , . ; :`; URL, ondalık sayı, saat ve kısaltmalar korunarak), `tr_TR` cümle başı büyük harf, cümle ortası tümcecik bağlamı dahil `mi/mı/mu/mü` soru eki ayrımı (`sence doğrumu yapıyorum? → sence doğru mu yapıyorum?`, iyelik ekleri korunarak) ve kapalı küme kesin TDK düzeltmeleri (`herşey → her şey`, `birşey → bir şey`, `hiçbirşey → hiçbir şey`, `herkez → herkes`, `yanlız → yalnız`, `yalnış → yanlış`, `sağol → sağ ol`, `hoşçakal → hoşça kal`, `ardarda → art arda`).
   - *v1 Kapsam Sınırı:* Sözdizimsel/anlamsal `de/da`, `ki` ve `kar/kâr` ayrımları yanlış düzeltmeleri sıfırda tutmak için otomatik kapsam dışındadır.
3. **`Çift Mod` *(Varsayılan)*:**
   - `Karakter` ve `Yazım` motorlarını bir arada çalıştırır; ek olarak bitişik ASCII soru ekleri ve TDK bileşiklerinde tek adımda ayırma ve karakter onarımı uygular (`ciktimi → çıktı mı`, `kotumu gorunuyor? → kötü mü görünüyor?`, `hersey → her şey`).

---

## Ölçülen Kalite ve Performans (`TitizEval`)

60 geliştirme ve regresyon vakası (`Datasets/dev_cases.json`) üzerinde `Release` derleme sonuçları:

| Ölçüt | Hedef | Ölçülen Sonuç |
| --- | --- | --- |
| Yanlış Pozitif Bozulma (Genel / Temiz Cümleler) | `<= %0,50` / `%0,00` | **`%0,00` (0/340)** / **`%0,00` (0/123)** |
| Özel Ad ve Yabancı Terim Koruması | `>= %99,00` (`Tier 1/2A: %100`) | **`%100,00` (48/48)** |
| Gerçek Hata Yakalama (`Bucket 1` / Genel) | `>= %92,00` / `>= %75,00` | **`%100,00` (70/70)** / **`%99,24` (131/132)** |
| Düzeltme Kesinliği (*Edit Precision*) | `>= %95,00` | **`%100,00` (131/131)** |
| Gecikme `p50 / p95` (273 krk. / 1.926 krk.) | `< 10 ms` / `< 25–80 ms` | **`0,702 / 0,847 ms`** · **`6,869 / 7,426 ms`** |

---

## Kurulum ve İlk Açılış (Gatekeeper)

GitHub Releases üzerinden indirdiğiniz `Titiz.app` paketini açarken macOS Gatekeeper ad-hoc imza uyarısı gösterebilir:

1. `Titiz.app` uygulamasını **Uygulamalar (`Applications`)** klasörüne sürükleyin.
2. Uygulamayı bir kez açmayı deneyip uyarı penceresini kapatın.
3. **Sistem Ayarları → Gizlilik ve Güvenlik** ekranının altındaki **"Yine de Aç"** düğmesiyle onaylayın.

> **macOS Sürüm Uyumluluğu:** `Package.swift` hedefi `macOS(.v14)` olarak tanımlıdır. macOS 26 ve üzerinde yerel Liquid Glass API'leri, macOS 14–15 sistemlerde `.ultraThinMaterial` / `.regularMaterial` uyumlu görsel katman kullanılır. (macOS 14–15 ortamları için çalışma zamanı uyumluluğu hedeflense de doğrudan o sürümlerde test edilene kadar doğrulanmamış kabul edilmelidir.)

---

## Mimari ve Geliştirme

Harici `.xcodeproj` gerektirmeden saf **Swift Package Manager (`Package.swift`)** ile yapılandırılmıştır:

```text
Titiz
├── Sources/TitizApp          # macOS Menü Çubuğu arayüzü (SwiftUI + AppKit odak/editör köprüsü + AppUpdater)
├── Sources/TitizCore         # Saf Swift deterministik düzeltme motoru (NFC, Tier 0–3, Karakter, Yazım, TDK)
├── Sources/CHunspell         # Gömülü C/C++ Hunspell motoru ve C köprü başlığı
├── Sources/TitizEval         # Geliştirme ve kör test seti ölçüm/gecikme CLI aracı
├── Tests/TitizCoreTests      # Birim ve regresyon test paketleri
├── assets/                   # İyonik sütun `T` macOS uygulama simgesi (`AppIcon.icns`) ve logo (`titiz-logo.png`)
└── scripts/                  # Çevrimdışı sözlük, simge ve `Titiz.app` / `.zip` / `.dmg` paketleme betikleri
```

Gereksinimler: macOS, Xcode ve Swift 6+ (son kullanıcı paketi harici Python/Node.js gerektirmez).

```bash
git clone https://github.com/GorkemSay/Titiz.git
cd Titiz

swift build                                  # Tüm hedefleri derle
swift test                                   # Birim ve regresyon testlerini çalıştır (52/52)
swift run -c release TitizEval --enforce-gates  # Kalite ve gecikme kapılarını doğrula
swift run TitizApp                           # Geliştirme modunda menü çubuğu uygulamasını başlat
./scripts/bundle-app.sh                      # dist/ altında Titiz.app, .zip ve .dmg paketlerini üret
```

---

## Lisans ve Üçüncü Taraf Bileşenler

- Titiz kaynak kodu **MIT Lisansı** ile lisanslanmıştır ([LICENSE](LICENSE)).
- Gömülü sözlükler, istatistiksel modeller ve açık veri kümelerinin lisans ve atıf bilgileri [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) dosyasında yer alır.
