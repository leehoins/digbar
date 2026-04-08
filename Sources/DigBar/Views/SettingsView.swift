import SwiftUI

struct SettingsView: View {
    @Bindable var dataManager: DataManager
    @State private var selectedSection: Tab = .binance
    @State private var form = SettingsForm()
    @State private var saved = false

    enum Tab: String, CaseIterable {
        case binance = "Binance"
        case kis = "KIS"
        case display = "디스플레이"
    }

    var body: some View {
        HSplitView {
            // Sidebar
            List(Tab.allCases, id: \.self, selection: $selectedSection) { s in
                Label(s.rawValue, systemImage: sectionIcon(s)).tag(s)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 130, idealWidth: 140, maxWidth: 160)

            // Content + Save footer
            VStack(spacing: 0) {
                switch selectedSection {
                case .binance: binanceSection
                case .kis:     kisSection
                case .display: displaySection
                }

                Divider()

                HStack {
                    if saved {
                        Label("저장됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    Spacer()
                    Button("저장") { saveAll() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: .command)
                }
                .padding(12)
            }
            .frame(minWidth: 360)
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { form = SettingsForm.load() }
    }

    // MARK: - Save

    private func saveAll() {
        form.commit()
        AppDelegate.applyAppearance()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { saved = false } }
        dataManager.stopAutoRefresh()
        dataManager.startAutoRefresh()
    }

    // MARK: - Binance

    private var binanceSection: some View {
        Form {
            Section {
                Toggle("활성화", isOn: $form.binanceRealEnabled)
                if form.binanceRealEnabled {
                    LabeledContent("표시 이름") {
                        TextField("Binance 실전", text: $form.binanceRealName)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    }
                    apiKeyRow("API Key",    text: $form.binanceRealKey)
                    apiKeyRow("API Secret", text: $form.binanceRealSecret, isSecret: true)
                }
            } header: { Text("실전투자") }

            Section {
                Toggle("활성화", isOn: $form.binanceDemoEnabled)
                if form.binanceDemoEnabled {
                    LabeledContent("표시 이름") {
                        TextField("Binance 모의투자", text: $form.binanceDemoName)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    }
                    apiKeyRow("Demo API Key",    text: $form.binanceDemoKey)
                    apiKeyRow("Demo API Secret", text: $form.binanceDemoSecret, isSecret: true)
                }
            } header: { Text("모의투자 (Demo Trading)") }

            Section {
                Link("Binance API 발급",       destination: URL(string: "https://www.binance.com/en/my/settings/api-management")!)
                Link("Demo Trading API 발급",  destination: URL(string: "https://www.binance.com/en/futures/BTCUSDT?type=demo")!)
                Text("모의투자 키는 Binance 메인 사이트 Demo Trading 메뉴에서 발급받으세요.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("도움말") }
        }
        .formStyle(.grouped)
    }

    // MARK: - KIS

    private var kisSection: some View {
        Form {
            Section {
                Toggle("활성화", isOn: $form.kisRealEnabled)
                if form.kisRealEnabled {
                    LabeledContent("표시 이름") {
                        TextField("KIS 실전투자", text: $form.kisRealName)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    }
                    apiKeyRow("App Key",    text: $form.kisRealKey)
                    apiKeyRow("App Secret", text: $form.kisRealSecret, isSecret: true)
                    LabeledContent("계좌번호") {
                        TextField("12345678-01", text: $form.kisRealAccount)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    }
                }
            } header: { Text("실전투자") }

            Section {
                Toggle("활성화", isOn: $form.kisDemoEnabled)
                if form.kisDemoEnabled {
                    LabeledContent("표시 이름") {
                        TextField("KIS 모의투자", text: $form.kisDemoName)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    }
                    apiKeyRow("App Key",    text: $form.kisDemoKey)
                    apiKeyRow("App Secret", text: $form.kisDemoSecret, isSecret: true)
                    LabeledContent("계좌번호") {
                        TextField("12345678-01", text: $form.kisDemoAccount)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    }
                }
            } header: { Text("모의투자") }

            Section {
                Link("KIS 오픈 API 신청", destination: URL(string: "https://apiportal.koreainvestment.com/")!)
                Text("계좌번호는 '-' 포함하여 입력 (예: 12345678-01)")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("도움말") }
        }
        .formStyle(.grouped)
    }

    // MARK: - Display

    private let refreshOptions = [10, 30, 60, 120, 300]
    private let tickerOptions  = [3, 5, 10, 30]

    private var displaySection: some View {
        Form {
            Section {
                Picker("화면 모드", selection: $form.appearanceMode) {
                    ForEach(AppSettings.AppearanceMode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.menu)
            } header: { Text("테마") }

            Section {
                Picker("표시 자산", selection: $form.statusBarAsset) {
                    ForEach(AppSettings.StatusBarAsset.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.menu)

                Picker("표시 형식", selection: $form.statusBarMode) {
                    ForEach(AppSettings.StatusBarMode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("아이콘") {
                    TextField("🐻", text: $form.iconEmoji)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: form.iconEmoji) { _, newValue in
                            // Keep only the first character cluster (one emoji)
                            if newValue.count > 1 {
                                form.iconEmoji = String(newValue.prefix(1))
                            }
                        }
                }
            } header: { Text("상태바") }

            Section {
                Picker("포트폴리오", selection: $form.refreshInterval) {
                    ForEach(refreshOptions, id: \.self) { s in
                        Text(s < 60 ? "\(s)초" : "\(s/60)분").tag(s)
                    }
                }
                .pickerStyle(.menu)

                Picker("가격 티커", selection: $form.tickerInterval) {
                    ForEach(tickerOptions, id: \.self) { s in
                        Text("\(s)초").tag(s)
                    }
                }
                .pickerStyle(.menu)

                Text("가격 티커: 관심종목·인기종목 가격만 갱신 (KIS 미포함). 포트폴리오는 상단 주기로 갱신.")
                    .font(.caption2).foregroundStyle(.secondary)
            } header: { Text("새로고침 주기") }

            Section {
                Picker("알림 재발송 주기", selection: $form.alertCooldownMinutes) {
                    Text("항상").tag(0)
                    Text("5분").tag(5)
                    Text("10분").tag(10)
                    Text("15분").tag(15)
                    Text("30분").tag(30)
                    Text("1시간").tag(60)
                }
                .pickerStyle(.menu)
                Text("목표가 달성 시 알림 재발송 최소 간격. '항상'은 갱신 주기마다 계속 알림.")
                    .font(.caption2).foregroundStyle(.secondary)
            } header: { Text("관심종목 알림") }

        }
        .formStyle(.grouped)
    }

    // MARK: - Reusable API key row

    @ViewBuilder
    private func apiKeyRow(_ label: String, text: Binding<String>, isSecret: Bool = false) -> some View {
        LabeledContent(label) {
            if isSecret {
                SecureField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            } else {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private func sectionIcon(_ s: Tab) -> String {
        switch s {
        case .binance: return "bitcoinsign.circle"
        case .kis:     return "building.columns"
        case .display: return "paintbrush"
        }
    }
}

// MARK: - SettingsForm

struct SettingsForm {
    var binanceRealEnabled: Bool = false
    var binanceRealKey: String = ""
    var binanceRealSecret: String = ""
    var binanceRealName: String = ""

    var binanceDemoEnabled: Bool = false
    var binanceDemoKey: String = ""
    var binanceDemoSecret: String = ""
    var binanceDemoName: String = ""

    var kisRealEnabled: Bool = false
    var kisRealKey: String = ""
    var kisRealSecret: String = ""
    var kisRealAccount: String = ""
    var kisRealName: String = ""

    var kisDemoEnabled: Bool = false
    var kisDemoKey: String = ""
    var kisDemoSecret: String = ""
    var kisDemoAccount: String = ""
    var kisDemoName: String = ""

    var alertCooldownMinutes: Int = 60
    var appearanceMode: AppSettings.AppearanceMode = .system
    var statusBarMode: AppSettings.StatusBarMode = .totalValue
    var statusBarAsset: AppSettings.StatusBarAsset = .usd
    var iconEmoji: String = "🐻"
    var refreshInterval: Int = 30
    var tickerInterval: Int = 5
    static func load() -> SettingsForm {
        let s = AppSettings.shared
        return SettingsForm(
            binanceRealEnabled:  s.binanceRealEnabled,
            binanceRealKey:      s.binanceRealAPIKey,
            binanceRealSecret:   s.binanceRealAPISecret,
            binanceRealName:     s.binanceRealName,
            binanceDemoEnabled:  s.binanceDemoEnabled,
            binanceDemoKey:      s.binanceDemoAPIKey,
            binanceDemoSecret:   s.binanceDemoAPISecret,
            binanceDemoName:     s.binanceDemoName,
            kisRealEnabled:      s.kisRealEnabled,
            kisRealKey:          s.kisRealAppKey,
            kisRealSecret:       s.kisRealAppSecret,
            kisRealAccount:      s.kisRealAccount,
            kisRealName:         s.kisRealName,
            kisDemoEnabled:      s.kisDemoEnabled,
            kisDemoKey:          s.kisDemoAppKey,
            kisDemoSecret:       s.kisDemoAppSecret,
            kisDemoAccount:      s.kisDemoAccount,
            kisDemoName:         s.kisDemoName,
            alertCooldownMinutes: s.alertCooldownMinutes,
            appearanceMode:      s.appearanceMode,
            statusBarMode:       s.statusBarMode,
            statusBarAsset:      s.statusBarAsset,
            iconEmoji:           s.iconEmoji,
            refreshInterval:     s.refreshInterval,
            tickerInterval:      s.tickerInterval,
        )
    }

    func commit() {
        let s = AppSettings.shared
        s.binanceRealEnabled   = binanceRealEnabled
        s.binanceRealAPIKey    = binanceRealKey
        s.binanceRealAPISecret = binanceRealSecret
        s.binanceRealName      = binanceRealName
        s.binanceDemoEnabled   = binanceDemoEnabled
        s.binanceDemoAPIKey    = binanceDemoKey
        s.binanceDemoAPISecret = binanceDemoSecret
        s.binanceDemoName      = binanceDemoName
        s.kisRealEnabled       = kisRealEnabled
        s.kisRealAppKey        = kisRealKey
        s.kisRealAppSecret     = kisRealSecret
        s.kisRealAccount       = kisRealAccount
        s.kisRealName          = kisRealName
        s.kisDemoEnabled       = kisDemoEnabled
        s.kisDemoAppKey        = kisDemoKey
        s.kisDemoAppSecret     = kisDemoSecret
        s.kisDemoAccount       = kisDemoAccount
        s.kisDemoName          = kisDemoName
        s.alertCooldownMinutes = alertCooldownMinutes
        s.appearanceMode       = appearanceMode
        s.statusBarMode        = statusBarMode
        s.statusBarAsset       = statusBarAsset
        s.iconEmoji            = iconEmoji
        s.refreshInterval      = refreshInterval
        s.tickerInterval       = tickerInterval
    }
}
