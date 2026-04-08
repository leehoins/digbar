import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // 헤더
                VStack(alignment: .leading, spacing: 4) {
                    Text("DigBar 사용 가이드")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("투자 포트폴리오를 메뉴바에서 한눈에 확인하세요.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                // 1. 기본 사용법
                HelpSection(title: "🖱️ 기본 사용법") {
                    HelpRow(label: "좌클릭", description: "팝업 창을 열거나 닫습니다.")
                    HelpRow(label: "우클릭", description: "새로고침, 설정, 도움말 등 메뉴를 표시합니다.")
                    HelpRow(label: "상단 메뉴바", description: "총 자산 금액과 등락률을 실시간으로 표시합니다. 설정에서 KRW/USD/둘 다 표시 방식을 바꿀 수 있습니다.")
                    HelpRow(label: "자동 새로고침", description: "설정에서 지정한 주기(기본 30초)마다 데이터를 자동으로 갱신합니다.")
                }

                // 2. 포트폴리오 탭
                HelpSection(title: "💼 포트폴리오 탭") {
                    HelpRow(label: "계좌 카드", description: "KIS(한국투자증권)와 Binance 계좌별로 카드가 표시됩니다. 카드 제목은 설정에서 원하는 이름으로 변경할 수 있습니다.")
                    HelpRow(label: "보유 종목 목록", description: "카드를 펼치면 보유 중인 종목과 수익률이 표시됩니다. 각 종목을 클릭하면 차트를 볼 수 있습니다.")
                    HelpRow(label: "색상 의미", description: "초록색은 수익, 빨간색은 손실을 나타냅니다.")
                    HelpRow(label: "자산 히스토리", description: "최근 24시간 자산 변화를 선 차트로 확인할 수 있습니다. 앱 실행 중에만 기록되며, 데이터가 쌓일수록 차트가 정확해집니다.")
                }

                // 3. 시장 지수 탭
                HelpSection(title: "📊 시장 지수 탭") {
                    HelpRow(label: "지수 목록", description: "미국(S&P500, 나스닥, 다우), 한국(코스피, 코스닥), 암호화폐(BTC, ETH 등) 주요 지수를 한눈에 볼 수 있습니다.")
                    HelpRow(label: "차트 보기", description: "지수 항목을 클릭하면 캔들스틱 차트가 펼쳐집니다.")
                    HelpRow(label: "표시 설정", description: "설정에서 시장 지수 탭 표시 여부를 켜거나 끌 수 있습니다.")
                }

                // 4. 차트 사용법
                HelpSection(title: "📈 차트 사용법") {
                    HelpRow(label: "인터벌 선택", description: "드롭다운 메뉴에서 1분, 3분, 5분, 10분, 15분, 30분, 1시간, 4시간, 1일, 1주 중 선택할 수 있습니다.")
                    HelpRow(label: "캔들 색상", description: "초록 캔들은 양봉(종가 > 시가), 빨간 캔들은 음봉(종가 < 시가)을 나타냅니다.")
                    HelpRow(label: "마우스 오버", description: "캔들 위에 마우스를 올리면 시가·고가·저가·종가(OHLC) 정보가 표시됩니다.")
                }

                // 5. API 설정
                HelpSection(title: "🔑 API 설정") {
                    Text("설정 창(⌘,)에서 각 계좌의 API 키를 등록합니다.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Binance")
                                .fontWeight(.semibold)
                            HelpRow(label: "API Key / Secret", description: "Binance 웹사이트 → 계정 → API 관리에서 발급합니다. 읽기 전용 권한으로 설정하면 더 안전합니다.")
                            HelpRow(label: "모의투자(Testnet)", description: "Binance Testnet에서 별도 API 키를 발급하여 사용합니다.")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("한국투자증권 (KIS)")
                                .fontWeight(.semibold)
                            HelpRow(label: "App Key / Secret", description: "한국투자증권 OpenAPI 포털(apiportal.koreainvestment.com)에서 앱을 등록하면 발급됩니다.")
                            HelpRow(label: "계좌번호 형식", description: "\"12345678-01\" 형식으로 입력합니다. 앞 8자리가 계좌번호, 뒤 2자리가 상품코드입니다.")
                            HelpRow(label: "모의투자", description: "한국투자증권 OpenAPI 포털에서 모의투자 전용 App Key/Secret을 별도로 발급받아야 합니다.")
                        }
                    }
                }

                // 6. FAQ
                HelpSection(title: "❓ 자주 묻는 질문") {
                    HelpRow(
                        label: "\"토큰 대기 중\" 메시지가 뜨면?",
                        description: "KIS API는 분당 1회 토큰 발급 제한이 있습니다. 잠시 기다리면 자동으로 재시도합니다."
                    )
                    HelpRow(
                        label: "KIS 모의투자 오류가 반복되면?",
                        description: "실전/모의 동시 조회 시 초당 요청 제한(EGW00201)이 발생할 수 있습니다. 앱이 자동으로 1.5초 후 재시도하므로 잠시 기다리면 됩니다."
                    )
                    HelpRow(
                        label: "데이터가 오래된 것 같으면?",
                        description: "우클릭 메뉴에서 \"새로고침\"을 선택하거나, 설정에서 자동 새로고침 주기를 짧게 조정하세요."
                    )
                    HelpRow(
                        label: "자산 히스토리 차트에 데이터가 없으면?",
                        description: "히스토리는 앱 실행 중에 15초 간격으로 기록됩니다. 앱을 처음 실행했거나 오랫동안 닫혀 있었다면 데이터가 부족할 수 있습니다."
                    )
                    HelpRow(
                        label: "API 키를 변경한 후 오류가 나면?",
                        description: "설정 창에서 새 키를 저장한 뒤 앱을 재시작하거나 새로고침하면 적용됩니다."
                    )
                }

                Spacer(minLength: 8)
            }
            .padding(28)
        }
        .frame(minWidth: 480, minHeight: 400)
    }
}

// MARK: - Sub-views

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            content()
        }
    }
}

private struct HelpRow: View {
    let label: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .fontWeight(.medium)
                .frame(width: 160, alignment: .leading)
                .foregroundStyle(.primary)
            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .font(.subheadline)
    }
}
