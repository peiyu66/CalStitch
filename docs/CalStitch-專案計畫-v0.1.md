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
- 最近一次已核對安裝的實機版本為 [0.1 (8)](development/version-history.md#section-43)。該輪已做模擬器試測，並確認 Air 上的版號；沒有由助手在實機啟動或操作個人資料。
- GitHub Pages 已提供中英文產品文件，網站部署不會改動 App。
- [上架文件草稿](CalStitch-上架文件草稿.md)另存；草稿不作為正式提交或發布確認。

## 3. 下一輪與待驗證

| 項目 | 狀態 |
| --- | --- |
| [農曆閏月與小月](development/rules.md#section-44) | 行為已確認，新算法待實作。 |
| [群組匯入授權分流](development/calendar-contacts.md#section-45) | 主要流程已實作，首次提示與系統設定返回仍待下一輪驗收。 |
| [首頁規則的下次日期與開始時間](development/interface.md#section-46) | 待修改。 |
| [時區清單字母索引與搜尋列](development/rules.md#section-47) | 待修改。 |
| [遺留事件下拉更新](development/calendar-contacts.md#section-48) | 待修改。 |
| [整批移除的逐筆預覽與確認](development/interface.md#section-49) | 待修改。 |

較早的技術驗證項目及驗收方式保留在[建置與驗證](development/build-and-test.md)，實際完成範圍以版本紀錄為準。

## 4. 後續工作

- [英文本地化與日期格式](development/rules.md#section-11)：中文介面穩定後再做；網站已有英文文件不代表 App 已支援英文。
- [跨帳號同步及日期邊界](development/build-and-test.md#section-7)：保留 iCloud／Google 事件標記往返、大量事件寫入、期間與子規則邊界等查核；首頁目前只開啟行事曆，尚未驗證定位指定日期。
- [上架前核對](CalStitch-上架文件草稿.md)：公開網站已有隱私聲明；App 內入口仍須換成正式內容。公開支援聯絡方式、隱私權資訊清單及 App Store Connect 資料須在送審前確認。

## 5. 開發文件

- [排程規則與日期引擎](development/rules.md)
- [行事曆與通訊錄整合](development/calendar-contacts.md)
- [介面與操作流程](development/interface.md)
- [建置與驗證](development/build-and-test.md)
- [版本與決策紀錄](development/version-history.md)
