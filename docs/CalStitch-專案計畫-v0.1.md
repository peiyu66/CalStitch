# CalStitch 專案計畫

[回開發文件索引](https://peiyu66.github.io/CalStitch/development.html)

## 1. 產品定位與首版範圍

CalStitch 是 iPhone 上的**行事曆規則工具**。使用者在 CalStitch 設定規則；計算結果寫入原本使用的 Apple 行事曆或已在 iPhone 同步的 Google 行事曆。它不取代原本的行事曆，不做月曆介面或事件瀏覽器，也不依賴自建後台。

首版要支援：
- 西元定期事件，以及農曆規則的用途（生日、紀念日、拜拜等）；用途不另設日期類型。
- 從二十四節氣挑選需要的項目，寫進個人的行事曆；不必訂閱整本節日行事曆。
- 一條規則可延伸出相對於基準日的其他日期，並隨基準日變動重算。
- 從通訊錄挑選聯絡人，將生日匯入為規則；套用後可在個人行事曆產生同名生日事件。
- 規則改動或移除後，更新或撤除已不符合規則、由 CalStitch 建立的未來事件，而不是只追加新事件。

不列入首版：OpenAI 週重設、事件詳情瀏覽、多父且以任務完成狀態為條件的專案管理。直接串 Google API 或自建同步服務不在目前方案內。

## 2. 目前版本

- **App Store 版：1.0.1 (36)**，支援 iPhone 和 iPad；iPad 採雙欄，可透過私人 iCloud 同步規則與分類順序。參見 [App Store](https://apps.apple.com/tw/app/calstitch/id6838189548)。
- **實機開發版：1.0 (36)**，曾安裝於 iPhone Air 與 iPad Pro；與商店封存版的安裝及驗證紀錄分開。新開發以已上架的 1.0.1 (36) 程式為基準。
- App 支援中文及英文；中英文指南與按版本說明的隱私聲明已在 [GitHub Pages](https://peiyu66.github.io/CalStitch/) 上線。
- [上架文件草稿](CalStitch-上架文件草稿.md)保留既有商店文案與下次送審待辦；[開發決策紀錄](development/decision-log.md)區分規格、已實作及驗證情境。

## 3. 驗收結案

| 項目 | 狀態 |
| --- | --- |
| [農曆閏月與小月](development/rules.md#section-44) | 已結案；11 項排程測試通過。 |
| [群組匯入授權分流](development/calendar-contacts.md#section-45) | 已結案。 |
| [首頁規則的下次日期與開始時間](development/interface.md#section-46) | 已結案。 |
| [時區清單字母索引與搜尋列](development/rules.md#section-47) | 已結案。 |
| [遺留事件下拉更新](development/calendar-contacts.md#section-48) | 已結案。 |
| [整批移除的逐筆預覽與確認](development/interface.md#section-49) | 已結案。 |
| [英文本地化與日期格式](development/rules.md#section-11) | 已結案。 |

[建置與驗證](development/build-and-test.md)保留當時的驗收方法、已驗證範圍及未涵蓋情境，供日後回歸測試使用，不代表仍有未結案問題。

## 4. iCloud 規則同步與 iPad 介面

iPhone/iCloud 里程碑為 1.0 (25)；之後在獨立開發分支接續 iPad 雙欄。詳見 [iCloud 規則同步計畫](development/icloud-sync-plan.md)及[開發會議與決策紀錄](development/decision-log.md)。33 至 36 版的實際驗證範圍見[版本紀錄](development/version-history.md#current-versions)。
