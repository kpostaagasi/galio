import SwiftUI

/// First-launch window: what Galio does, which permissions it uses and why.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var screenGranted = AugmentOCR.hasPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("Galio'ya hoş geldin").font(.largeTitle.bold())
                    Text("League of Legends için macOS yardımcın").foregroundStyle(.secondary)
                }
            }
            OnboardingRow(icon: "person.3.fill", title: "Şampiyon seçimi",
                          text: "Takımının ihtiyacına göre 3–5 şampiyon önerisi, rün sayfaları (tek tıkla aktarma), sihirdar büyüleri, yetenek sırası ve eşyalar.")
            OnboardingRow(icon: "rectangle.on.rectangle", title: "Oyun içi katman",
                          text: "Oyunu Kenarlıksız veya Pencere modunda çalıştır. Katmanı ⌥⇧G ile gizleyip gösterebilir, ayarlardan saydamlık ve tıklama geçirgenliğini değiştirebilirsin.")
            OnboardingRow(icon: "text.viewfinder", title: "Ekran Kaydı izni (isteğe bağlı)",
                          text: "Sadece ARAM: Mayhem ve Arena'da \"Kartları tara\"ya bastığında üç güçlendirme kartının adını cihaz üzerinde okumak için. Görüntü kaydedilmez, hiçbir yere gönderilmez. İzin vermezsen elle arama kullanılabilir.")
            HStack {
                Button(screenGranted ? Loc.tr("Ekran Kaydı izni verildi") : Loc.tr("Ekran Kaydı izni iste")) {
                    screenGranted = AugmentOCR.requestPermission()
                }
                .disabled(screenGranted)
                if !screenGranted {
                    Button("Sistem Ayarları'nı aç") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            .padding(.leading, 40)
            OnboardingRow(icon: "checkmark.shield.fill", title: "Adil oyun",
                          text: "Galio oyuna tuş göndermez, oyun belleğini okumaz, diğer oyuncuların adlarını veya istatistiklerini göstermez. Güçlendirmelerde yalnızca seviye gösterilir.")
            Spacer(minLength: 0)
            HStack {
                Text("Galio isn't endorsed by Riot Games.").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Başla") {
                    onboardingDone = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 560)
    }
}

struct OnboardingRow: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let textKey: LocalizedStringKey

    init(icon: String, title titleKey: LocalizedStringKey, text textKey: LocalizedStringKey) {
        self.icon = icon
        self.titleKey = titleKey
        self.textKey = textKey
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey).font(.headline)
                Text(textKey).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
