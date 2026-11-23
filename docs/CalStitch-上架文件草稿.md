# CalStitch 上架文件草稿

內部檢閱版。依目前 0.1（14）候選版撰寫；送審前須按實際上傳版本再次核對。方括號是發布前要補的資料。

## 一、隱私權聲明（公開頁面文案）

**CalStitch 隱私權聲明**

生效日期：[正式發布日期]

開發者：[App Store 顯示的開發者姓名或名稱]

CalStitch 是 iPhone 的行事曆規則工具。你不需要建立 CalStitch 帳號。CalStitch 不把你的聯絡人、行事曆內容或規則傳給開發者，也不使用廣告、行為追蹤或第三方分析工具。

**行事曆。** 你選擇連接行事曆時，CalStitch 會向 iPhone 請求完整取用權限。這是為了列出目的行事曆、讀回並核對 App 管理的事件，以及預覽、更新或移除這些事件。CalStitch 會讀取日期、事件附註等資料，以辨識附有 CalStitch 標記的事件。「清除遺留事件」也會在畫面標示的日期範圍內檢查可寫入的行事曆，找出有標記但在本機沒有對應規則的事件。預覽與搜尋不會寫入行事曆；執行套用或確認刪除才會修改。

**通訊錄。** 「個別選人」使用 iPhone 的系統選人畫面，CalStitch 只會取得你這次選取的聯絡人，不要求開放整本通訊錄。「依群組匯入」需要完整取用權限；CalStitch 會讀取群組清單，選定群組後才讀取成員的姓名、暱稱（若有）與生日。你可以選姓名或暱稱作為事件標題的一部分；沒有暱稱時使用姓名。匯入的規則在 App 內保留標題、生日資料與聯絡人識別資料，供排程及辨識重複匯入。CalStitch 不會編輯你的通訊錄。

**儲存與同步。** 規則、設定及事件比對紀錄儲存在 App 的本機資料中。套用規則後，事件寫入你選的 iPhone 系統行事曆。如果該行事曆由 iCloud、Google 或其他帳號同步，事件會隨該行事曆同步，並依該帳號服務的隱私與共享設定處理。若選共享行事曆，有權查看該行事曆的人可能看到事件標題，例如匯入生日所用的姓名或暱稱。CalStitch 不需要你的 iCloud 或 Google 帳號密碼。

**管理權限與刪除資料。** 你可以在 iPhone 的「設定」撤銷 CalStitch 的行事曆或通訊錄權限。撤銷權限不會自動抹除已匯入的規則或已寫入的事件。規則可在 CalStitch 內移除；批次移除會一併移除可核對且尚未開始的相關事件，保留已開始的事件。移除 App 不會替你清除系統行事曆；如不需要留下事件，請在移除前用 CalStitch 清理，或在原行事曆中刪除。開發者不保有可代為刪除的行事曆或通訊錄副本。

**聯絡方式。** 隱私或使用問題請洽：[公開支援聯絡方式]。如你主動聯絡，我們會用你提供的聯絡方式和內容回覆及處理該問題。

## 二、使用說明（公開支援頁面文案）

### 建立規則

1. 在首頁按「＋」，選西元、農曆或節氣，設定週期與截止日期。
2. 填寫事件標題、分類和目的行事曆，設定整日或開始時間與持續期間。次類可留空。
3. 開啟「預覽事件」，核對已有和待變更的事件。按「套用」才寫入行事曆；回首頁可按「行事曆」查看日期前後的安排。

起始日是開始算排程的那一天，不一定是第一筆事件。例如每年五月第二個星期日的規則，起始日可設五月一日。要為事件排準備或後續事項，先套用主規則，再新增子規則並指定提前、同一天或延後。

### 選擇行事曆

首次按「連接行事曆」時，請在 iPhone 系統視窗授權完整取用。只有可寫入的行事曆可選；唯讀行事曆會列出但不能點。若 iCloud 或 Google 行事曆已在 iPhone 設定同步，不用在 CalStitch 再登入。第一次試用可先選一個專用的測試行事曆。

### 匯入生日

首頁按「匯入生日」。選「個別選人」只傳回這次勾選的人；選「依群組匯入」需完整取用通訊錄。首次可在系統視窗授權。已拒絕或僅部分取用時，按「開啟設定」變更權限再返回。

確認要匯入的西元或農曆生日及目的行事曆，並選擇用姓名或暱稱命名。預設「草稿」只存規則，不建立事件；「匯入後套用」會在你完成匯入時寫入事件。兩種方式都可在匯入前改選目的地。

### 批次調整與清除

「批次調整」可更改多條規則的分類、次類或期間；更改期間時先展開「預覽變更」。開啟「整批移除」只切換模式；按「套用」並在確認視窗選「移除」後，才會刪除所選規則及可核對的未開始事件。按「取消」不會刪除。

「清除遺留事件」用來找回已沒有本機規則的 CalStitch 事件。按照已過去與未到來分區，在勾選前確認事件和來源行事曆。若有其他裝置使用同一行事曆，請先確認事件沒有由另一台裝置管理。沒有 CalStitch 標記的同名事件不會列入。

### 節氣與目前限制

節氣資料可離線使用，涵蓋 1901–2100 年。設定的「預設時區」用於新建節氣規則；修改偏好不會搬動既有事件。農曆規則可依閏月及小月條件排程；套用前可在預覽中查看實際日期。

支援聯絡：[公開支援聯絡方式]

隱私權聲明：[公開網址]

## 三、App Store Connect 文案草稿

### 基本資料

- 名稱：CalStitch
- 平台：iOS（iPhone）
- Bundle ID：`org.peiyu66.CalStitch`
- 建議主分類：生產力（Productivity）
- 本版版權：2026 peiyu66（比照 Vista，已存入 Connect）

### 中文

**副標題：** 農曆生日、節氣與行事曆規則

**關鍵字：** 農曆生日,節氣,重複行程,週期,行事曆規則,紀念日,祭祀,閏月

**宣傳文字：** 在 CalStitch 設規則，在原本的行事曆看行程。只加入你選的節日、紀念日和聯絡人生日。

**描述：**

CalStitch 把農曆生日、節氣和定期事項排進你原本的 iPhone 行事曆。只加入想記的節日、紀念日和生日，不必訂閱整份節日行事曆，也不用開啟顯示所有聯絡人生日的行事曆。

- 用西元、農曆或節氣建立重複規則，也能安排每年五月第二個星期日這類日期。
- 用子規則把準備或後續事項排在主事件之前、當天或之後。
- 選擇要匯入的聯絡人生日，可用姓名或暱稱命名，先存成草稿或直接套用。
- 套用前預覽事件，並用分類和次類整理規則、批次調整。
- 使用 iPhone 已連結的可寫入行事曆，不必另建帳號或在 CalStitch 再登入。

- 行銷網址：https://peiyu66.github.io/CalStitch/
- 隱私政策網址：https://peiyu66.github.io/CalStitch/privacy.html
- 支援網址：https://peiyu66.github.io/CalStitch/support.html（公開回報方式為 GitHub Issues）

### English (U.S.)

**Subtitle:** Lunar & Recurring Events

**Keywords:** lunar,birthday,calendar,recurring,solar terms,anniversary,holiday,schedule,repeat

**Promotional text:** Set rules in CalStitch and see events in your iPhone calendar. Add just the holidays, anniversaries, and birthdays you want.

**Description:**

CalStitch adds lunar birthdays, solar terms, and recurring events to the iPhone calendar you already use. Add only the holidays, anniversaries, and birthdays you want, without subscribing to a full holiday calendar or showing every contact’s birthday.

- Create recurring rules based on Gregorian dates, lunar dates, or solar terms. Schedule dates such as the second Sunday in May.
- Use linked rules to schedule prep or follow-up events before, on, or after a main event.
- Import selected birthdays by name or nickname. Save them as drafts or apply them to a calendar.
- Preview calendar changes before applying them. Organize rules into categories and subcategories and update them in batches.
- Choose a writable calendar already set up on your iPhone. No CalStitch account or separate sign-in is needed.

- Marketing URL: https://peiyu66.github.io/CalStitch/en/
- Privacy Policy URL: https://peiyu66.github.io/CalStitch/en/privacy.html
- Support URL: https://peiyu66.github.io/CalStitch/en/support.html（公開回報方式為 GitHub Issues）

**App Review Notes（英文草稿）：**

No account or sign-in is required. To test the main flow, open CalStitch, tap +, create a Gregorian rule, and choose a writable calendar after granting full Calendar access. Preview the planned events, then tap Apply to write them. Preview alone makes no changes. Birthday import is optional: individual selection uses the system contact picker; only group import requests full Contacts access. To test without granting Contacts access, create a rule manually. We recommend using a dedicated test calendar.

**截圖建議：**

以虛構資料展示首頁規則清單、農曆／節氣規則編輯、事件預覽、生日匯入。避免顯示真實姓名、生日、活動名稱或私人行事曆。

## 四、送審前核對（內部，不發布）

- App Store Connect：CalStitch，Apple ID：6838189548，iOS 1.0 為「準備提交」。已存中英文商店文字、行銷網址、主分類「生產力工具」、不需登入及審查備註；年齡分級 4+；「不收集資料」僅存草稿，尚未發布。
- 主要語言為中文，保留英文資料。免費，已設定全部 175 個現有地區（含法國），並依 Apple 的全部地區設定涵蓋未來新增地區。
- 中英文 GitHub Pages 隱私與支援網址已設定；審查聯絡資料僅存於 Connect，不公開。Connect 已存八張截圖，維持審核通過後自動發布。隱私標籤未發布、未送審。1.0（15）僅改版號；Xcode 確認上傳成功，Connect 顯示上傳完成；TestFlight 列出 1.0（15），狀態是「缺少出口合規資訊」。建置未選入送審草稿。
- 中國大陸安全評估與人工智慧生成合成內容欄位都顯示缺少資訊，ICP 欄位留空；尚未判定適用性，不視為完成。DSA 帳戶顯示非交易商，App 層級狀態仍待核對。


- 設定頁已連至對應語言的公開隱私權聲明，網站支援頁使用公開 GitHub Issues 並提醒不要貼個人資料。正式版文件部署後核對中英文連結可開，且與 App Store Connect 一致。參考 [App Review Guidelines §5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)、[App Privacy 欄位](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/) 和 [版本資訊欄位](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)。
- 隱私標籤目前可先以「未收集資料」作為待確認的答案，不代表 App 不讀取資料。以正式送審版重新核對是否有開發者或整合服務收到資料、以及支援流程如何運作；確認後再填寫及發布。參考 [Apple 對資料收集的定義](https://developer.apple.com/app-store/app-privacy-details/)。
- 專案使用 UserDefaults；僅改版號的 1.0（15）封存未含隱私權資訊清單。送審前依 Apple 要求核對並補齊 `PrivacyInfo.xcprivacy`，確認自有偏好設定的適用理由（候選 `CA92.1`）與是否有其他須申報 API。這與公開隱私權聲明是不同文件。參考 [Apple Required Reason API](https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api)。
- 封存已核對版本號與 iPhone 裝置類型；處理完成後，在 Connect 核對該版狀態、加密問卷及其他必要欄位。發布隱私標籤與提交審查均不是上傳建置的一部分。

### 加密與法國供應

已核對 0.1（14）Release 的程式碼、Xcode 套件及執行檔連結；1.0（15）僅改版號，沒有自帶加密實作或第三方加密函式庫。聯絡人與行事曆使用 Apple 系統框架；若使用者已開啟 iCloud 或 Google 行事曆同步，由 iPhone 的既有帳號處理。依 [Apple 的加密出口文件要求](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)，不需要因加密排除法國。實際送審建置仍須再次核對，並可在確認後設定 `ITSAppUsesNonExemptEncryption` 為 `NO`，或依 Connect 建置版本的實際問卷回答。
