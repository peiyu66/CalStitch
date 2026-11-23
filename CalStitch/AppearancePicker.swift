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
        let chinese: String
        let english: String
        var title: String { L10n.text(chinese, english) }

        init(_ id: String, _ chinese: String, _ english: String) {
            self.id = id
            self.chinese = chinese
            self.english = english
        }
    }

    private struct Swatch: Identifiable {
        let id: UInt32
        let chinese: String
        let english: String
        let color: AppearanceColor
        var title: String { L10n.text(chinese, english) }

        init(_ chinese: String, _ english: String, _ rgb: UInt32) {
            self.id = rgb
            self.chinese = chinese
            self.english = english
            color = AppearanceColor(
                red: Double((rgb >> 16) & 255) / 255,
                green: Double((rgb >> 8) & 255) / 255,
                blue: Double(rgb & 255) / 255
            )
        }
    }

    private static let symbols = [
        Choice("calendar", "行事曆", "Calendar"), Choice("folder", "資料夾", "Folder"), Choice("tag", "標籤", "Tag"),
        Choice("star", "星星", "Star"), Choice("heart", "愛心", "Heart"), Choice("bell", "提醒", "Bell"),
        Choice("birthday.cake", "生日蛋糕", "Birthday Cake"), Choice("gift", "禮物", "Gift"), Choice("sparkles", "閃光", "Sparkles"),
        Choice("house", "家", "Home"), Choice("person.2", "人物", "People"), Choice("briefcase", "公事包", "Briefcase"),
        Choice("book", "書本", "Book"), Choice("graduationcap", "學習", "Education"), Choice("list.bullet", "清單", "List"),
        Choice("moon", "月亮", "Moon"), Choice("sun.max", "太陽", "Sun"), Choice("leaf", "葉子", "Leaf"),
        Choice("flame", "火焰", "Flame"), Choice("cup.and.saucer", "茶杯", "Cup and Saucer"), Choice("fork.knife", "餐具", "Cutlery"),
        Choice("airplane", "飛機", "Airplane"), Choice("car", "汽車", "Car"), Choice("figure.walk", "步行", "Walking"),
        Choice("dumbbell", "健身", "Dumbbell"), Choice("music.note", "音符", "Music Note"), Choice("cart", "購物", "Shopping Cart"),
        Choice("clock", "時鐘", "Clock"), Choice("checkmark.circle", "完成", "Checkmark"), Choice("flag", "旗幟", "Flag")
    ].filter { UIImage(systemName: $0.id) != nil }

    private static let swatches = [
        Swatch("灰藍", "Slate Blue", 0x637892), Swatch("藍", "Blue", 0x2663A6), Swatch("青綠", "Teal", 0x287775),
        Swatch("綠", "Green", 0x3C7743), Swatch("金", "Gold", 0xA06C24), Swatch("橘", "Orange", 0xAD552A),
        Swatch("紅", "Red", 0xB04452), Swatch("紫", "Purple", 0x795895)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            preview
            VStack(alignment: .leading, spacing: 10) {
                heading(L10n.text("圖示", "Icon"), isDefault: appearance.symbol == nil) { appearance.symbol = nil }
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
                heading(L10n.text("顏色", "Color"), isDefault: appearance.color == nil) { appearance.color = nil }
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
                ColorPicker(L10n.text("自訂顏色", "Custom Color"), selection: customColor, supportsOpacity: false)
            }
            Button(L10n.text("全部恢復預設", "Reset All to Defaults")) { appearance = RuleAppearance() }
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
                Text(L10n.text("預覽", "Preview")).font(.caption).foregroundStyle(.secondary)
                Text(title.isEmpty ? L10n.text("尚未命名", "Untitled") : title).font(.body.weight(.semibold))
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
            Button(isDefault ? L10n.text("使用預設", "Using Default") : L10n.text("恢復預設", "Reset to Default"), action: reset)
                .font(.subheadline)
                .disabled(isDefault)
                .accessibilityLabel(isDefault ? L10n.text("\(title)使用預設", "Using the default for \(title.lowercased())") : L10n.text("\(title)恢復預設", "Reset \(title.lowercased()) to default"))
        }
    }
}
