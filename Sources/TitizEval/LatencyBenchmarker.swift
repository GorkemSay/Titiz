import Foundation
import TitizCore

/// Latency distribution statistics in milliseconds.
public struct LatencyStats: Codable, Sendable, Equatable {
    public let characterCount: Int
    public let iterations: Int
    public let minMs: Double
    public let p50Ms: Double
    public let p95Ms: Double
    public let maxMs: Double
    public let meanMs: Double

    public init(
        characterCount: Int,
        iterations: Int,
        minMs: Double,
        p50Ms: Double,
        p95Ms: Double,
        maxMs: Double,
        meanMs: Double
    ) {
        self.characterCount = characterCount
        self.iterations = iterations
        self.minMs = minMs
        self.p50Ms = p50Ms
        self.p95Ms = p95Ms
        self.maxMs = maxMs
        self.meanMs = meanMs
    }
}

/// Short (300-char) and long (2,000-char) latency benchmark results.
public struct LatencyReport: Codable, Sendable, Equatable {
    public let short: LatencyStats
    public let long: LatencyStats

    public var shortPasses: Bool {
        short.p50Ms < EvalThresholds.maxP50LatencyMs && short.p95Ms < EvalThresholds.maxShortP95LatencyMs
    }

    public var longPasses: Bool {
        long.p50Ms < EvalThresholds.maxP50LatencyMs && long.p95Ms < EvalThresholds.maxLongP95LatencyMs
    }

    public var allGatesPass: Bool {
        shortPasses && longPasses
    }

    public init(short: LatencyStats, long: LatencyStats) {
        self.short = short
        self.long = long
    }
}

/// Measures p50 and p95 latency on deterministic 300-char and 2,000-char Turkish+mixed inputs.
public enum LatencyBenchmarker {
    // ~300 characters: realistic Turkish + English technical terms + URL + CamelCase + punctuation
    public static let shortSample: String =
        "Intel ekibinden MaviKutu icin yeni surum notlari ve API belgeleri geldi. " +
        "Bugun `swift test` calistirdik, https://tdk.gov.tr/sozluk adresindeki ornekleri inceledik. " +
        "Yarin toplanti varmi? Ayrica \"Search\" dugmesini de kontrol edelim, cunku acil driver guncellemesi bekliyoruz!"

    // ~2,000 characters: multi-paragraph mixed Turkish/ASCII/code-switched realistic document
    public static let longSample: String = {
        let paragraph1 =
            "Merhaba ekip, bugunku surum toplantisinda Intel, Nvidia ve Apple tarafindan gelen son teknik geri " +
            "bildirimleri ayrintili bicimde degerlendirdik. Ozellikle MaviKutu modulu icindeki API yanit sureleri " +
            "`TitizCore` boru hatti uzerinde olculdu ve https://github.com/GorkemSay/Titiz deposuna aktarildi. " +
            "Kullanicilar \"Search\" ve 'Gönder' alanlarina yarin disari cikacagim gibi ifadeler yazdiginda sistemin " +
            "dogru olani bozmamasi bizim icin bir numarali kuraldir.\n\n"
        let paragraph2 =
            "Gelistirici belgelerinde Sources/TitizCore/TitizEngine.swift dosyasi ile ./scripts/bundle-app.sh " +
            "betiginin gorevleri adim adim anlatildi. Ayrica gorkemsay@protonmail.com adresine duzenli durum ozeti " +
            "gonderiliyor. macOS uzerinde MenuBarExtra penceresinin odak ve kopyala yapistir kisayollarini her " +
            "koşulda sorunsuz calistirmasi hedefleniyor; bu sayede hem hiz hem guvenilirlik onemli olcude artiyor. " +
            "Can'a ve Istanbul ekibine de guncel notlari ilettik.\n\n"
        let paragraph3 =
            "Test asamasinda @gorkemsay ve #Turkce etiketleriyle paylasilan orneklerde GPT-4, iOS, macOS, Xcode " +
            "ve TDK kisaltmalarinin hicbir kosulda degistirilmemesi kontrol edildi. Saat 14:30'da yapilacak " +
            "oturumda son karar verilecek. Herkes hazir mi, yoksa ek bir driver veya feedback dosyasi daha " +
            "eklememiz gerekecekmi? Toplamda 3.14 oraninda bir iyilesme goruldu ve elde edilen sonuclar ekip " +
            "tarafindan oldukca memnuniyet verici bulundu.\n\n"
        let paragraph4 =
            "Kapanis notu olarak: The Last of Us, Red Dead Redemption ve Visual Studio Code gibi cok sozcuklu ozel " +
            "adlar ile ekonomi, samimi, resmi, kimi, yirmi, acemi, ilmi ve daimi gibi gecerli Turkce kelimeler " +
            "yanlislikla bolunmemelidir. Yarinki degerlendirmede tum metrikleri temiz bicimde raporlayacagiz " +
            "ve herhangi bir supheli durumda ozgun metni korumayi tercih edecegiz. Ayrica Spotify ve Netflix " +
            "entegrasyonu icin hazirlanan test senaryolari da bu aksam gozden gecirilecek, eksik kalan " +
            "noktalar tamamlandiktan ve tum dogrulama adimlari gectikten sonra surum yayini icin nihai onay alinacak."
        return paragraph1 + paragraph2 + paragraph3 + paragraph4
    }()

    /// Benchmarks `engine.correct(..., mode: .combined)` on both short and long samples.
    public static func measure(using engine: TitizEngine, iterations: Int = 50, warmup: Int = 5) -> LatencyReport {
        let count = max(1, iterations)
        let shortStats = measureSample(shortSample, using: engine, iterations: count, warmup: warmup)
        let longStats = measureSample(longSample, using: engine, iterations: count, warmup: warmup)
        return LatencyReport(short: shortStats, long: longStats)
    }

    /// Computes exact nearest-rank percentile on an already-sorted or unsorted array of samples.
    public static func percentile(_ values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let sorted = values.sorted()
        let clampedP = min(max(p, 0.0), 100.0)
        if clampedP == 0.0 { return sorted[0] }
        let rank = Int(ceil((clampedP / 100.0) * Double(sorted.count)))
        let index = min(max(0, rank - 1), sorted.count - 1)
        return sorted[index]
    }

    private static func measureSample(
        _ sample: String,
        using engine: TitizEngine,
        iterations: Int,
        warmup: Int
    ) -> LatencyStats {
        for _ in 0..<max(0, warmup) {
            _ = engine.correct(sample, mode: .combined)
        }

        let clock = ContinuousClock()
        var samplesMs: [Double] = []
        samplesMs.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let start = clock.now
            _ = engine.correct(sample, mode: .combined)
            let elapsed = start.duration(to: clock.now)
            let ms = Double(elapsed.components.seconds) * 1_000.0
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
            samplesMs.append(ms)
        }

        let sorted = samplesMs.sorted()
        let sum = sorted.reduce(0.0, +)
        return LatencyStats(
            characterCount: sample.count,
            iterations: iterations,
            minMs: sorted.first ?? 0.0,
            p50Ms: percentile(sorted, p: 50.0),
            p95Ms: percentile(sorted, p: 95.0),
            maxMs: sorted.last ?? 0.0,
            meanMs: sum / Double(sorted.count)
        )
    }
}
