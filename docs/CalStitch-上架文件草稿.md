# CalStitch 上架文件草稿

App Store 1.0.1 (36) 已上架，支援 iPhone 和 iPad。下列保留本次中英文文案供下次準備送審時參照。

## 一、隱私權聲明（公開頁面文案）

以中英文 [隱私權聲明](../website/privacy.html)／[Privacy Policy](../website/en/privacy.html) 為文案來源。發佈前比對 [App Store「資料未收集」判定](development/icloud-sync-plan.md#privacy-label-data-not-collected)及實際建置資料流。

## 二、使用說明（公開支援頁面文案）

以中英文 [使用說明](../website/guide.html)／[User Guide](../website/en/guide.html) 為準，避免重複維護。

## 三、App Store Connect 文案草稿

### 基本資料

- 名稱：CalStitch
- 候選版平台：iPhone、iPad
- Bundle ID：`org.peiyu66.CalStitch`
- 建議主分類：生產力（Productivity）
- 本版版權：2026 peiyu66（比照 Vista，已存入 Connect）

### 中文

**副標題：** 農曆生日、節氣與行事曆規則

**關鍵字：** 農曆生日,節氣,重複行程,週期,行事曆規則,紀念日,祭祀,閏月

**宣傳文字：** 在 CalStitch 設規則，在原本的行事曆看行程。只加入你選的節日、紀念日和聯絡人生日。

**描述：**

CalStitch 把農曆生日、節氣和定期事項排進你原本使用的行事曆。只加入想記的節日、紀念日和生日，不必訂閱整份節日行事曆，也不用開啟顯示所有聯絡人生日的行事曆。

- 用西元、農曆或節氣建立重複規則，也能安排每年五月第二個星期日這類日期。
- 用子規則把準備或後續事項排在主事件之前、當天或之後。
- 挑選要匯入的生日，預設用暱稱，確認後直接加入指定行事曆。
- 套用前預覽事件，並用分類和次類整理規則、批次調整。
- 使用裝置上的可寫入行事曆，不必另建 CalStitch 帳號。使用同一個 Apple 帳號時，可透過私人 iCloud 在 iPhone 和 iPad 同步規則。

- 行銷網址：https://peiyu66.github.io/CalStitch/
- 隱私政策網址：https://peiyu66.github.io/CalStitch/privacy.html
- 支援網址：https://peiyu66.github.io/CalStitch/support.html（公開回報方式為 GitHub Issues）

### English (U.S.)

**Subtitle:** Lunar & Recurring Events

**Keywords:** lunar,birthday,calendar,recurring,solar terms,anniversary,holiday,schedule,repeat

**Promotional text:** Set rules in CalStitch and see events in your iPhone calendar. Add just the holidays, anniversaries, and birthdays you want.

**Description:**

CalStitch adds lunar birthdays, solar terms, and recurring events to the calendar you already use. Add only the holidays, anniversaries, and birthdays you want, without subscribing to a full holiday calendar or showing every contact’s birthday.

- Create recurring rules based on Gregorian dates, lunar dates, or solar terms. Schedule dates such as the second Sunday in May.
- Use linked rules to schedule prep or follow-up events before, on, or after a main event.
- Import selected birthdays into a calendar of your choice. Titles use nicknames by default, or names if no nickname is available.
- Preview calendar changes before applying them. Organize rules into categories and subcategories and update them in batches.
- Choose a writable calendar already set up on your device. No CalStitch account is needed. With the same Apple Account, sync rules between iPhone and iPad using your private iCloud database.

- Marketing URL: https://peiyu66.github.io/CalStitch/en/
- Privacy Policy URL: https://peiyu66.github.io/CalStitch/en/privacy.html
- Support URL: https://peiyu66.github.io/CalStitch/en/support.html（公開回報方式為 GitHub Issues）

**App Review Notes（英文草稿）：**

No CalStitch account is required. Rule sync uses the user’s private iCloud database when an Apple Account is signed in on the device. To test the main flow, open CalStitch, tap +, create a Gregorian rule, and choose a writable calendar after granting full Calendar access. Preview the planned events, then tap Apply to write them. Preview alone makes no changes. Birthday import is optional: individual selection uses the system contact picker; only group import requests full Contacts access. To test without granting Contacts access, create a rule manually. We recommend using a dedicated test calendar.

**截圖建議：**

以虛構資料展示首頁規則清單、農曆／節氣規則編輯、事件預覽、生日匯入。避免顯示真實姓名、生日、活動名稱或私人行事曆。

## 四、下次送審前核對

- 下次準備送審時，在中文關鍵字加上「排程」，保留「重複行程」。這是下次的待辦，未修改 1.0.1 的商店關鍵字。
- 隱私標籤現行為「資料未收集」。依上架建置確認只有使用者的私人 iCloud 同步，沒有新增開發者或合作方可存取的資料流；檢查封存的隱私權資訊清單及 UserDefaults 申報。
- 確認正式 CloudKit、iPhone 和 iPad 裝置支援與審查資料一致，並補齊兩個平台的截圖。展示使用虛構聯絡人及測試行事曆。
- 重新核對候選版的出口合規：18 版的問卷不直接沿用。候選版使用 CloudKit 與系統 CryptoKit SHA-256 產生生日比對碼，仍須依候選封存、Apple 要求與地區核對；不據此自行調整設定或地區。參見 [Apple：加密出口合規](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)。
