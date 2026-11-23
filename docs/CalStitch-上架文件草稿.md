# CalStitch 上架文件草稿

內部檢閱版。依 0.1（8）的程式行為撰寫。方括號是發布前要補的資料。尚未加入的功能不列為上架特色。

## 一、隱私權聲明（公開頁面文案）

**CalStitch 隱私權聲明**

生效日期：[正式發布日期]

開發者：[App Store 顯示的開發者姓名或名稱]

CalStitch 是 iPhone 的行事曆規則工具。你不需要建立 CalStitch 帳號。CalStitch 不把你的聯絡人、行事曆內容或規則傳給開發者，也不使用廣告、行為追蹤或第三方分析工具。

**行事曆。** 你選擇連接行事曆時，CalStitch 會向 iPhone 請求完整取用權限。這是為了列出目的行事曆、讀回並核對 App 管理的事件，以及預覽、更新或移除這些事件。CalStitch 會讀取日期、事件附註等資料，以辨識附有 CalStitch 標記的事件。「清除遺留事件」也會在畫面標示的日期範圍內檢查可寫入的行事曆，找出有標記但在本機沒有對應規則的事件。預覽與搜尋不會寫入行事曆；執行套用或確認刪除才會修改。

**通訊錄。** 「個別選人」使用 iPhone 的系統選人畫面，CalStitch 只會取得你這次選取的聯絡人，不要求開放整本通訊錄。「依群組匯入」需要完整取用權限；CalStitch 會讀取群組清單，選定群組後才讀取成員的姓名與生日。匯入的規則在 App 內保留標題、生日資料與聯絡人識別資料，供排程及辨識重複匯入。CalStitch 不會編輯你的通訊錄。

**儲存與同步。** 規則、設定及事件比對紀錄儲存在 App 的本機資料中。套用規則後，事件寫入你選的 iPhone 系統行事曆。如果該行事曆由 iCloud、Google 或其他帳號同步，事件會隨該行事曆同步，並依該帳號服務的隱私與共享設定處理。若選共享行事曆，有權查看該行事曆的人可能看到事件標題，例如匯入生日所用的姓名。CalStitch 不需要你的 iCloud 或 Google 帳號密碼。

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

確認要匯入的西元或農曆生日及目的行事曆。預設「草稿」只存規則，不建立事件；「匯入後套用」會在你完成匯入時寫入事件。兩種方式都可在匯入前改選目的地。

### 批次調整與清除

「批次調整」可更改多條規則的分類、次類或期間；更改期間時先展開「預覽變更」。開啟「整批移除」只切換模式；按「套用」並在確認視窗選「移除」後，才會刪除所選規則及可核對的未開始事件。按「取消」不會刪除。

「清除遺留事件」用來找回已沒有本機規則的 CalStitch 事件。按照已過去與未到來分區，在勾選前確認事件和來源行事曆。若有其他裝置使用同一行事曆，請先確認事件沒有由另一台裝置管理。沒有 CalStitch 標記的同名事件不會列入。

### 節氣與目前限制

節氣資料可離線使用，涵蓋 1901–2100 年。設定的「預設時區」用於新建節氣規則；修改偏好不會搬動既有事件。測試版若遇到尚未支援的農曆閏月或小月條件，會提示不能套用。正式發布前需按最終版本更新本段。

支援聯絡：[公開支援聯絡方式]

隱私權聲明：[公開網址]

## 三、App Store Connect 文案草稿

**名稱：** CalStitch

**副標題：** 用規則安排農曆與重複行程

**建議分類：** 生產力

**關鍵字：** 農曆生日,二十四節氣,重複行程,行事曆規則,月週期,節日提醒,紀念日

**宣傳文字：**

在 CalStitch 設規則，在原本的行事曆看行程。整理農曆生日、節氣和重複事項，先預覽，再套用。

**描述：**

CalStitch 幫你把生日、節氣和定期事項排進 iPhone 原本的行事曆。你在 CalStitch 管理規則，不必另外維護一份日曆。

- 用西元、農曆或節氣建立重複規則，指定起始日、截止日和事件長度。
- 建立子規則，把準備或後續事項排在主事件之前、當天或之後。
- 從通訊錄匯入生日，先存成草稿，或確認後套用到指定行事曆。
- 套用前預覽事件，並以分類和次類整理規則、批次調整。
- 使用 iPhone 已連結的可寫入行事曆。無須另外建立帳號或在 CalStitch 再登入。

**App Review Notes（英文草稿）：**

No account or sign-in is required. To test the main flow, open CalStitch, tap +, create a Gregorian rule, and choose a writable calendar after granting full Calendar access. Preview the planned events, then tap Apply to write them. Preview alone makes no changes. Birthday import is optional: individual selection uses the system contact picker; only group import requests full Contacts access. To test without granting Contacts access, create a rule manually. We recommend using a dedicated test calendar.

**截圖建議：**

以虛構資料展示首頁規則清單、農曆／節氣規則編輯、事件預覽、生日匯入。避免顯示真實姓名、生日、活動名稱或私人行事曆。

## 四、送審前核對（內部，不發布）

- 確認公開的隱私權聲明、支援頁網址和可聯絡方式。將設定頁目前的隱私權聲明草稿換成可存取的正式入口，與 App Store Connect 使用同一份政策。參考 [App Review Guidelines §5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)、[App Privacy 欄位](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/) 和 [版本資訊欄位](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)。
- 隱私標籤目前可先以「未收集資料」作為待確認的答案，不代表 App 不讀取資料。以正式送審版重新核對是否有開發者或整合服務收到資料、以及支援流程如何運作；確認後再填寫及發布。參考 [Apple 對資料收集的定義](https://developer.apple.com/app-store/app-privacy-details/)。
- 目前專案使用 UserDefaults，尚未見隱私權資訊清單。正式 Archive 前加入並核對 `PrivacyInfo.xcprivacy`，確認自有偏好設定的適用理由（候選 `CA92.1`）與是否有其他須申報 API。這與公開隱私權聲明是不同文件。參考 [Apple Required Reason API](https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api)。
- 依上架版重新核對支援 iOS 版本、語言、畫面、農曆規則及審查步驟。未完成的閏月與小月排程不先寫成上架功能。確認版權署名、公開支援聯絡方式、隱私及支援網址，並完成 App Store Connect 的年齡分級、加密問卷、審查聯絡資料及發布方式。暫未填寫或送審。
