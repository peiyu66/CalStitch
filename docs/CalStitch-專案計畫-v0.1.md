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

## 2. 目前正式版

- 目前正式版基準為 [1.0 (15)](development/version-history.md#build-15)。與 iPhone Air 上最後核對的 [0.1 (14)](development/version-history.md#build-14) 是同一套程式，只改版號。
- 開發與試用回饋已全數結案。已實作而未再收到回饋的項目，依使用者確認視為沒有新問題，不保留為開發待辦。
- GitHub Pages 提供中英文產品文件，App 支援中文及英文。
- 1.0 (15) 已上傳 App Store Connect，尚未送審或在 App Store 上架。上架行政及合規流程另見[上架文件草稿](CalStitch-上架文件草稿.md)，不列入開發待辦。

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
