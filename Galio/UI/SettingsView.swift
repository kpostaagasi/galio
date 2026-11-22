import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var overlay: OverlayController

    @AppStorage(OverlayController.opacityKey) private var opacity = 0.92
    @AppStorage(OverlayController.clickThroughKey) private var clickThrough = false
    @AppStorage(OverlayController.autoShowKey) private var autoShow = true
    @AppStorage(OverlayController.hotKeyEnabledKey) private var hotKeyEnabled = true
    @AppStorage("dataAutoRefresh") private var dataAutoRefresh = true
    @AppStorage("lockfilePath") private var lockfilePath = ""
    @AppStorage(Loc.languageDefaultsKey) private var language = "system"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        TabView {
            Form {
                Section("Oyun içi katman") {
                    Toggle("Oyun akışına göre otomatik göster", isOn: $autoShow)
                    Toggle("Tıklama geçirgen (fare oyuna gider)", isOn: $clickThrough)
                        .onChange(of: clickThrough) { overlay.applySettings() }
                    LabeledContent("Saydamlık") {
                        Slider(value: $opacity, in: 0.3...1.0)
                            .frame(width: 200)
                            .onChange(of: opacity) { overlay.applySettings() }
                            .accessibilityLabel("Katman saydamlığı")
                    }
                    Toggle("Kısayol ⌥⇧G ile göster/gizle", isOn: $hotKeyEnabled)
                        .onChange(of: hotKeyEnabled) { overlay.updateHotKey() }
                    Text("Katman yalnızca Kenarlıksız veya Pencere modunda oyunun üstünde görünür.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Katman", systemImage: "rectangle.on.rectangle") }

            Form {
                Section("Genel") {
                    Picker("Dil", selection: $language) {
                        Text("Sistem").tag("system")
                        Text("Türkçe").tag("tr")
                        Text("English").tag("en")
                    }
                    .onChange(of: language) { Loc.applyLanguageOverride(language) }
                    Text("Dil değişikliği Galio yeniden açılınca uygulanır.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Oturum açılışında başlat", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("League istemcisi") {
                    TextField("lockfile yolu (boş = varsayılan)", text: $lockfilePath, prompt: Text(Lockfile.defaultPath))
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Genel", systemImage: "gearshape") }

            Form {
                Section("Öneri verisi") {
                    LabeledContent("Yama", value: store.patch)
                    LabeledContent("Kaynak", value: store.source.rawValue)
                    if let date = store.lastRefresh {
                        LabeledContent("Son kontrol", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Toggle("Açılışta otomatik güncelle", isOn: $dataAutoRefresh)
                    HStack {
                        Button("Şimdi güncelle") { Task { await store.refresh(force: true) } }
                            .disabled(store.isRefreshing)
                        if store.isRefreshing { ProgressView().controlSize(.small) }
                    }
                    if let err = store.refreshError {
                        Text(err).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Veri", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520, height: 400)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text("Galio").font(.largeTitle.bold())
                        Text(Loc.tr("Sürüm %@", version)).foregroundStyle(.secondary)
                    }
                }
                Text("macOS için League of Legends yardımcısı: şampiyon seçimi önerileri, rün sayfaları, yetenek sırası, eşya ve güçlendirme ipuçları.")
                Card {
                    Text("Adil oyun ilkeleri").font(.headline)
                    Text("Galio oyuna asla tuş basmaz veya tıklamaz, oyun belleğini okumaz, gizli bilgi ve diğer oyuncuların istatistiklerini göstermez. Güçlendirmelerde kazanma oranı değil yalnızca seviye (S–D) gösterilir. Rün ve eşya seti aktarımı sadece senin tıklamanla, oyun dışında yapılır.")
                        .foregroundStyle(.secondary)
                }
                Text("Galio isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games, and all associated properties are trademarks or registered trademarks of Riot Games, Inc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("github.com/kpostaagasi/galio", destination: URL(string: "https://github.com/kpostaagasi/galio")!)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }
}
