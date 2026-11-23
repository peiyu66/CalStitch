# CalStitch 專案計畫 v0.1

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

## 2. 目前進度

- 已有 iPhone 功能測試版，尚未在 App Store 上架。
- 最近一次已核對安裝的實機版本為 [0.1 (14)](development/version-history.md#build-14)。iPhone Air 上是依 App 語言顯示的 Release 候選版；未代為啟動或操作實機資料。
- [1.0 (15)](development/version-history.md#build-15) 由同一來源只改版號封存並上傳 Connect；未送審，尚未在 App Store 上架。
- GitHub Pages 已提供中英文產品文件，App 支援中文及英文。網站部署不會改動 App。
- [上架文件草稿](CalStitch-上架文件草稿.md)另存；草稿不作為正式提交或發布確認。

## 3. 0.1 (9) 的驗收項目

| 項目 | 狀態 |
| --- | --- |
| [農曆閏月與小月](development/rules.md#section-44) | 已實作，新增 11 項排程測試。 |
| [群組匯入授權分流](development/calendar-contacts.md#section-45) | 已補首次提示；實機由系統設定返回仍待驗收。 |
| [首頁規則的下次日期與開始時間](development/interface.md#section-46) | 已實作，待實機回饋。 |
| [時區清單字母索引與搜尋列](development/rules.md#section-47) | 已實作，待實機回饋。 |
| [遺留事件下拉更新](development/calendar-contacts.md#section-48) | 已實作，待實機回饋。 |
| [整批移除的逐筆預覽與確認](development/interface.md#section-49) | 已實作，待實機回饋。 |

較早的技術驗證項目及驗收方式保留在[建置與驗證](development/build-and-test.md)，實際完成範圍以版本紀錄為準。

## 4. 後續工作

- [英文本地化與日期格式](development/rules.md#section-11)：0.1 (9) 已加入英文；仍待實機試用回饋。
- [跨帳號同步及日期邊界](development/build-and-test.md#section-7)：保留 iCloud／Google 事件標記往返和大量事件寫入的實機查核。日期邊界的現行行為見該節。首頁目前只開啟行事曆，不提供指定日期定位。
- [上架前核對](CalStitch-上架文件草稿.md)：0.1 (9) 設定已加入中英文隱私權聲明與支援入口。私下支援聯絡方式、隱私權資訊清單及 App Store Connect 資料須在送審前確認。
