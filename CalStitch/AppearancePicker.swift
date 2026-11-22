import SwiftUI
import UIKit

struct RuleAppearance: Codable, Hashable {
    var symbol: String? = nil
    var color: AppearanceColor? = nil

    var isDefault: Bool { symbol == nil && color == nil }

    func symbol(or fallback: String) -> String {
        guard let symbol, UIImage(systemName: symbol) != nil else { return fallback }
        return symbol
    }

    func tint(or fallback: Color) -> Color { color?.swiftUIColor ?? fallback }
}

struct AppearanceColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.channel(red)
        self.green = Self.channel(green)
        self.blue = Self.channel(blue)
    }

    init?(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        self.init(red: Double(red), green: Double(green), blue: Double(blue))
    }

    private static func channel(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(1, max(0, value)) * 255).rounded() / 255
    }
}

struct AppearancePicker: View {
    let title: String
    @Binding var appearance: RuleAppearance
    let defaultSymbol: String
    let defaultColor: Color

    private struct Choice: Identifiable {
        let id: String
        let title: String
        init(_ id: String, _ title: String) {
            self.id = id
            self.title = title
        }
    }

    private struct Swatch: Identifiable {
        let title: String
        let color: AppearanceColor
        var id: String { title }
        init(_ title: String, _ rgb: UInt32) {
            self.title = title
            color = AppearanceColor(
                red: Double((rgb >> 16) & 255) / 255,
                green: Double((rgb >> 8) & 255) / 255,
                blue: Double(rgb & 255) / 255
            )
        }
    }

    private static let symbols = [
        Choice("calendar", "行事曆"), Choice("folder", "資料夾"), Choice("tag", "標籤"),
        Choice("star", "星星"), Choice("heart", "愛心"), Choice("bell", "提醒"),
        Choice("birthday.cake", "生日蛋糕"), Choice("gift", "禮物"), Choice("sparkles", "閃光"),
        Choice("house", "家"), Choice("person.2", "人物"), Choice("briefcase", "公事包"),
        Choice("book", "書本"), Choice("graduationcap", "學習"), Choice("list.bullet", "清單"),
        Choice("moon", "月亮"), Choice("sun.max", "太陽"), Choice("leaf", "葉子"),
        Choice("flame", "火焰"), Choice("cup.and.saucer", "茶杯"), Choice("fork.knife", "餐具"),
        Choice("airplane", "飛機"), Choice("car", "汽車"), Choice("figure.walk", "步行"),
        Choice("dumbbell", "健身"), Choice("music.note", "音符"), Choice("cart", "購物"),
        Choice("clock", "時鐘"), Choice("checkmark.circle", "完成"), Choice("flag", "旗幟")
    ].filter { UIImage(systemName: $0.id) != nil }

    private static let swatches = [
        Swatch("灰藍", 0x637892), Swatch("藍", 0x2663A6), Swatch("青綠", 0x287775),
        Swatch("綠", 0x3C7743), Swatch("金", 0xA06C24), Swatch("橘", 0xAD552A),
        Swatch("紅", 0xB04452), Swatch("紫", 0x795895)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            preview
            VStack(alignment: .leading, spacing: 10) {
                heading("圖示", isDefault: appearance.symbol == nil) { appearance.symbol = nil }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    ForEach(Self.symbols) { choice in
                        let selected = appearance.symbol == choice.id
                        Button {
                            appearance.symbol = choice.id
                        } label: {
                            Image(systemName: choice.id)
                                .font(.system(size: 19))
                                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.09),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    if selected {
                                        RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                heading("顏色", isDefault: appearance.color == nil) { appearance.color = nil }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
                    ForEach(Self.swatches) { swatch in
                        let selected = appearance.color == swatch.color
                        Button {
                            appearance.color = swatch.color
                        } label: {
                            Circle()
                                .fill(swatch.color.swiftUIColor)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color.white)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.title)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                ColorPicker("自訂顏色", selection: customColor, supportsOpacity: false)
            }
            Button("全部恢復預設") { appearance = RuleAppearance() }
                .disabled(appearance.isDefault)
        }
    }

    private var preview: some View {
        let tint = appearance.tint(or: defaultColor)
        return HStack(spacing: 12) {
            Image(systemName: appearance.symbol(or: defaultSymbol))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("預覽").font(.caption).foregroundStyle(.secondary)
                Text(title.isEmpty ? "尚未命名" : title).font(.body.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var customColor: Binding<Color> {
        Binding {
            appearance.tint(or: defaultColor)
        } set: { color in
            if let rgb = AppearanceColor(color) { appearance.color = rgb }
        }
    }

    private func heading(_ title: String, isDefault: Bool, reset: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(isDefault ? "使用預設" : "恢復預設", action: reset)
                .font(.subheadline)
                .disabled(isDefault)
                .accessibilityLabel(isDefault ? "\(title)使用預設" : "\(title)恢復預設")
        }
    }
}
