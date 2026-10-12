import GoogleMobileAds
import SwiftUI

/// 一覧の下に敷くバナー。全画面広告は出さない（えさをあげる操作の途中に割り込むことになるため）。
///
/// 追跡の許可（ATT）は求めず、非パーソナライズ広告だけを出す。
/// 求めるにはマニフェストに配信元のドメインを並べる必要があり、並べると断った人の端末では
/// 接続ごと遮断されて広告が出なくなる（MiniCity と同じ判断）。
struct AdBanner: View {
    // ponytail: Google のテスト用 ID。本物の広告ユニットを作ったら差し替える。
    static let unit = "ca-app-pub-3940256099942544/2934735716"

    var body: some View {
        BannerAdView()
            .frame(width: AdSizeBanner.size.width, height: AdSizeBanner.size.height)
            .frame(maxWidth: .infinity)
            .background(.bar)
    }
}

struct BannerAdView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let view = BannerView(adSize: AdSizeBanner)
        view.adUnitID = AdBanner.unit
        view.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        view.load(Request())
        return view
    }

    func updateUIView(_ view: BannerView, context: Context) {}
}
