# Tính năng mới — SE Knowledge

Tài liệu tổng hợp các chức năng vừa được thêm vào dự án, kèm các phần chính của
từng chức năng và vị trí file tương ứng.

Mốc so sánh: từ commit `9a4aa22` (add note) tới `b56c90e`.

- [Phần A — Đã commit: AI Chat + Graph RAG](#phần-a--đã-commit-ai-chat--graph-rag)
- [Phần B — Đang làm dở: Backend Obsidian + Ràng buộc xoá](#phần-b--đang-làm-dở-backend-obsidian--ràng-buộc-xoá)
- [Trạng thái kiểm thử](#trạng-thái-kiểm-thử)
- [Việc còn lại](#việc-còn-lại)

---

## Phần A — Đã commit: AI Chat + Graph RAG

| Commit | Nội dung |
| --- | --- |
| `dc3b230` | Thêm ngữ cảnh Graph RAG cho AI chat |
| `660be56` | Trả lời dạng stream + mở rộng cách truy hồi môn học |
| `b56c90e` | Quy tắc prompt gia sư + trích dẫn môn học bấm được |

Tổng cộng: **+1173 / −169 dòng**, 2 file mới trong `lib/`, 1 file test mới.

### 1. Graph RAG — trích subgraph liên quan thay vì gửi cả CSDL

**File chính:** `lib/services/graph_rag_service.dart` (330 dòng, mới)
**Model:** `lib/models/graph_rag_context.dart` (mới)

Vấn đề: nhét toàn bộ bảng môn học vào mọi prompt thì tốn token, AI bị cắt câu
trả lời giữa chừng và hay trả lời lan man sang môn không liên quan.

Giải pháp: chỉ gửi kèm phần đồ thị liên quan trực tiếp tới câu hỏi.

**Các phần chính:**

| Thành phần | Vai trò |
| --- | --- |
| `findSeeds()` | Tìm môn "hạt giống" từ câu hỏi — hai đường vào song song |
| `_rankByKeyword()` | Chấm điểm môn theo từ khoá, có ngưỡng cắt tương đối |
| `_conceptsOf()` | Tách câu hỏi thành nhóm khái niệm, bỏ stopword, gộp cụm 2 từ |
| `_expand()` | BFS 2 chiều 2 bước từ seed để lấy subgraph |
| `_renderPrompt()` | Render subgraph thành văn bản nhét vào system prompt |
| `GraphRagSummary` | Phần tóm tắt nhẹ để hiển thị UI + lưu kèm tin nhắn |

**Cách nhận diện môn học trong câu hỏi:**

1. **Theo mã môn** — regex `\b[A-Z]{2,4}\d{2,4}[A-Z]?\b` bắt `PRF192`, `CSD201`.
   Đây là tín hiệu chắc chắn nhất, được ưu tiên xếp trước.
2. **Theo từ khoá** — đối chiếu với mã, tên và mô tả môn. Bắt buộc phải có, vì
   phần lớn câu hỏi thật không đọc mã môn ra mà hỏi theo chủ đề
   ("em muốn theo hướng AI thì học gì trước").

**Các xử lý đáng chú ý trong phần so khớp từ khoá:**

- **Bỏ dấu tiếng Việt** — bảng `_deaccent` quy `Toán rời rạc`, `toan roi rac`,
  `TOÁN RỜI RẠC` về cùng một dạng.
- **Bảng viết tắt** `_aliases` — `AI` → `artificial intelligence` / `trí tuệ
  nhân tạo` / `machine learning`, `CSDL` → `database`, cùng `OOP`, `DSA`, `SQL`...
  Thiếu bảng này thì hỏi "hướng AI" không khớp nổi môn nào, vì môn tên
  *Artificial Intelligence* chứ không tên *AI*.
- **Chống nhập nhằng viết tắt** — `ai` chỉ được bung nghĩa khi người dùng gõ
  hoa cả cụm. "hướng AI" được mở rộng, còn "Ai là người dạy môn này" thì không.
- **Cụm 2 từ liền nhau** — `cau truc`, `do thi` phân biệt tốt hơn từ đơn và
  không bị stopword cắt mất. Quan trọng với tiếng Việt vì bỏ dấu xong "đồ" và
  "đó" đều thành "do".
- **Chống khớp bừa chuỗi con** — từ đơn phải khớp trọn một token (hoặc là tiền
  tố từ 3 ký tự trở lên), nếu không `ai` sẽ khớp vào `mail`, `detail`.
- **Danh sách stopword tiếng Việt** (~70 từ) — lọc `em`, `muốn`, `học`, `môn`,
  `nào`, `gì`... để chúng không khớp vào mô tả và kéo theo môn chẳng liên quan.

**Trần giới hạn:**

| Hằng số | Giá trị | Lý do |
| --- | --- | --- |
| `maxKeywordSeeds` | 5 | Câu hỏi chung chung không kéo cả chục môn làm phình ngược ngữ cảnh |
| `maxNodes` | 24 | BFS 2 bước từ nhiều seed dễ chạm gần hết đồ thị, mất ý nghĩa thu hẹp |
| `hops` | 2 | Mặc định, truyền được từ ngoài vào |

**Nhánh fallback:** khi không suy ra được môn nào (`seeds` rỗng), gửi **toàn bộ**
đồ thị và bật cờ `isFallbackFullGraph`. Cố tình không cắt bớt — lúc đã không
đoán được câu hỏi nhắm vào đâu thì đưa thiếu tai hại hơn đưa dư.

### 2. Trả lời dạng stream (SSE)

**File chính:** `lib/services/ai_service.dart` (viết lại phần lớn, 279 → 335 dòng)

Chữ hiện dần từng mẩu thay vì đứng im chờ trọn câu trả lời.

**Các phần chính:**

| Thành phần | Vai trò |
| --- | --- |
| `ask()` | Điểm vào duy nhất: dựng ngữ cảnh → chọn provider → stream về |
| `_consumeSse()` | Đọc Server-Sent Events, ghép mẩu chữ, bắn ra `onDelta` |
| `_streamGemini()` | Endpoint `:streamGenerateContent?alt=sse`, header `x-goog-api-key` |
| `_streamOpenAi()` | Endpoint `/chat/completions` với `stream: true` |
| `extract` callback | Phần khác nhau giữa 2 provider — bóc text khỏi 1 chunk JSON |
| `_errorMessage()` | Dịch HTTP status sang câu tiếng Việt dễ hiểu |

**Hai callback cho UI:**

- `onContext(summary)` — gọi **ngay khi trích xong ngữ cảnh**, trước lúc chờ
  mạng. Nhờ vậy khung Graph RAG hiện lên trước cả chữ đầu tiên.
- `onDelta(delta)` — gọi mỗi lần nhận thêm một mẩu chữ.

**Các chi tiết quan trọng:**

- `timeout = 45s` là **khoảng chờ giữa hai chunk**, không phải tổng thời gian —
  nhờ vậy câu trả lời dài vẫn chạy thoải mái mà vẫn bắt được lúc treo mạng.
- `maxHistoryMessages = 8` — gửi trọn lịch sử thì càng chat lâu prompt càng
  phình ra, đi ngược lại chính mục tiêu tiết kiệm token của Graph RAG.
- `_recentHistory()` lọc bỏ các tin **báo lỗi** cũ, vì chúng không phải câu trả
  lời thật và làm nhiễu ngữ cảnh.
- Lỗi HTTP được dịch rõ ràng: `401/403` → "API key sai hoặc không có quyền",
  `404` → "Không tìm thấy model (kiểm tra lại tên model trong Cài đặt)",
  `429` → "Vượt quá giới hạn gọi API".

### 3. Prompt gia sư + trích dẫn môn học bấm được

**File:** `lib/services/ai_service.dart` (`_systemPrompt`),
`lib/views/chat/ai_chat_page.dart` (`_LinkedAnswerText`)

Đây là một cặp khoá chặt với nhau, sửa bên này phải sửa bên kia.

**Phía prompt** — bắt AI viết mã môn trong hai ngoặc vuông:

> "Mỗi lần nhắc tới một môn học, viết mã môn trong hai ngoặc vuông, ví dụ
> `[[CSD201]]`, để ứng dụng biến nó thành liên kết bấm được."

Các quy tắc khác trong system prompt:

- Trả lời bằng tiếng Việt, ngắn gọn, đi thẳng vào việc.
- Gợi ý lộ trình phải đánh số theo đúng thứ tự học, nêu lý do dựa trên quan hệ
  tiên quyết.
- **Chỉ dùng dữ liệu được cung cấp**, không bịa môn không có trong danh sách.
- Thiếu dữ liệu thì nói thẳng là chưa có trong CSDL, không suy đoán.

**Phía UI** — `_LinkedAnswerText` bóc wiki link thành `TextSpan` bấm được:

- Dùng lại chính `ObsidianService.wikiLinkPattern` (tức `MarkdownParser`) chứ
  không viết regex riêng — một nguồn sự thật duy nhất.
- Chấp nhận cả `[[CSD201|Cấu trúc dữ liệu]]` lẫn `[[CSD201#Mục]]`.
- Mã không tra được trong `graph.byCode` thì in ra chữ thường, không tạo link chết.
- Bấm vào mã môn thì gọi `AppState.openNoteTab(subject)`.
- **`TapGestureRecognizer` được cache theo mã môn và `dispose()` khi huỷ widget** —
  tạo mới mỗi lần build sẽ rò rỉ bộ nhớ, vì `TextSpan` không tự huỷ recognizer của nó.

### 4. Khung "Graph RAG" dưới mỗi câu trả lời

**File:** `lib/views/chat/ai_chat_page.dart` (`_RagContextPanel`, `_AnswerActions`)

Panel xổ ra / thu gọn được, hiển thị chính xác app đã gửi gì cho AI:

- Các mã môn khớp được (`matchedCodes`) dưới dạng thẻ
- Số node / số cạnh của subgraph
- Ước lượng token (`_estimateTokens`, heuristic ~4 ký tự mỗi token)
- Thời gian trích xuất (ms)
- Cờ fallback khi phải dùng toàn bộ đồ thị

**Hàng nút dưới mỗi câu trả lời** (`_AnswerActions`):

- **Xem trên đồ thị** — chọn sẵn môn đầu tiên trong ngữ cảnh rồi chuyển tab, mở
  đồ thị lên là node đó đã được highlight.
- **Sao chép** — chép câu trả lời vào clipboard.

`GraphRagSummary` được lưu kèm `ChatMessage` (có `toJson` / `fromJson`) nên mở
lại phiên chat cũ vẫn thấy đúng ngữ cảnh đã dùng, mà không cần giữ lại cả subgraph.

### 5. API key và model tách riêng theo từng provider

**File:** `lib/services/settings_service.dart`, `lib/views/settings/settings_page.dart`

Lỗi cũ: Gemini và OpenAI dùng **chung** một ô lưu key, đổi tab qua lại vẫn hiện
lại cùng một key và ghi đè lẫn nhau.

**Sửa:**

- Khoá lưu đổi thành dạng `<khoá>_<provider>`, qua `_apiKeyStorageKey()` và
  `_modelStorageKey()`.
- `getApiKey([provider])` / `setApiKey(key, [provider])` / `getModel` / `setModel`
  nhận thêm tham số provider, mặc định lấy provider đang chọn.
- `_migrateLegacyAiConfig()` — chạy **một lần** lúc `init()`, dời giá trị cũ sang
  đúng slot của provider đang chọn lúc đó rồi xoá khoá cũ. Người đang dùng bản cũ
  không bị mất key.
- `_switchProvider()` ở UI — đổi tab thì **tải lại** đúng key/model đã lưu của
  provider đó, thay vì giữ nguyên ô đang gõ.

---

## Phần B — Đang làm dở: Backend Obsidian + Ràng buộc xoá

> Phần này **chưa commit**, đang nằm ở working tree.

### 1. Bóc tách cú pháp Markdown

**File:** `lib/services/markdown_parser.dart` (452 dòng, mới)

Thuần Dart — không `dart:io`, không SQLite, không Flutter. Nhờ vậy chạy được
bằng `flutter test` mà không cần Visual Studio, và là **nơi duy nhất trong app
chứa logic regex**; mọi tầng khác chỉ gọi vào đây.

| Thành phần | Vai trò |
| --- | --- |
| `WikiLink` | Một wiki link đã bóc tách, kèm `start` / `end` / `section` |
| `MdTag` | Một hashtag đã bóc tách, hỗ trợ tag lồng nhiều cấp |
| `ParsedNote` | Một file `.md` đã bóc xong: front matter + body + links + tags |
| `splitFrontMatter()` | Tách YAML đầu file, hỗ trợ cả danh sách 1 dòng lẫn nhiều dòng |
| `parseLinks()` / `parseTags()` | Dò link và tag kèm vị trí ký tự |
| `maskCode()` | Che khối code trước khi dò, giữ nguyên độ dài để vị trí vẫn khớp |
| `sectionSpans()` | Chia body theo heading để biết link nằm dưới mục nào |

**Các ca khó đã xử lý:**

- Link và tag nằm trong khối code, code inline hay URL đều bị bỏ qua.
- Heading Markdown và số thứ tự dạng `#1` không bị nhận nhầm thành tag.
- Tag có dấu tiếng Việt, tag lồng nhiều cấp.
- Tag khai trong front matter, cả dạng danh sách một dòng lẫn danh sách YAML
  xuống dòng.
- `mergeMarkdown()` giữ nguyên phần người dùng tự viết khi ghi đè (có test
  chạy lại nhiều lần vẫn cho cùng kết quả).

Kết quả trả về **kèm vị trí ký tự và tên section cha**, để tầng UI vẽ được nút
bấm, thẻ màu và dropdown mà không phải parse lại chuỗi lần nữa. Có sẵn
`buildBacklinkIndex()` và `buildTagIndex()` — hiện chưa view nào dùng.

### 2. Đọc/ghi Vault và Export/Import

**File:** `lib/services/obsidian_service.dart` (829 dòng)

| Nhóm | Hàm |
| --- | --- |
| Đọc/ghi file | `scanVault()`, `readNote()`, `saveNote()`, `deleteNote()` |
| Sinh markdown | `buildMarkdown()`, `mergeMarkdown()`, `_buildFrontMatter()` |
| Xuất ra Vault | `exportSubject()`, `exportAll()`, `_writeIndexNote()` |
| Nhập từ Vault | `planImport()` → `applyPlan()`, hoặc `importVault()` gộp cả hai |

`planImport()` trả về `VaultSyncPlan` cho phép **xem trước** thay đổi (thêm gì,
sửa gì, gỡ cạnh nào) rồi mới `applyPlan()` — không ghi mù vào CSDL.

Đã nối vào `app_state.dart` và chạy được ở `vault_page.dart`.

### 3. Kiểm tra ràng buộc trước khi xoá môn

**File:** `lib/services/subject_delete_guard.dart` (382 dòng, mới)

`ON DELETE CASCADE` của SQLite xoá sạch mọi cạnh liên quan mà không báo một
tiếng nào. Với đồ thị tiên quyết thì đó là mất dữ liệu âm thầm: xoá một môn nằm
giữa chuỗi `A → B → C` là cắt đôi lộ trình học, và không có cách nào hoàn tác.

| Thành phần | Vai trò |
| --- | --- |
| `DeleteRisk` | 3 mức: `safe` / `warning` (môn lá) / `danger` (có môn phụ thuộc) |
| `DeleteStrategy` | `cascade` (xoá thẳng) hoặc `rewire` (nối tắt vá chỗ đứt) |
| `DeleteImpact` | Kết quả phân tích — dữ liệu để dựng hộp thoại cảnh báo |
| `RewireSuggestion` | Một cạnh nối tắt được đề xuất, ví dụ `PRF192 → PRJ301` |
| `analyze()` / `analyzeGraph()` | Phân tích, chỉ đọc. Bản trên graph tách riêng để test không cần mở DB |
| `execute()` | Xoá theo phương án đã chọn, nằm trọn trong một transaction |

**Nội dung `DeleteImpact` đưa cho hộp thoại:**

- Danh sách môn tiên quyết sẽ mất cạnh
- Danh sách môn đang phụ thuộc (nhóm bị ảnh hưởng nặng nhất)
- Môn sẽ trở thành node đơn độc trên đồ thị
- Đề xuất nối tắt an toàn, kèm danh sách cặp bị chặn và lý do
- Đường dẫn file `.md` trong Vault, nếu có

**Hai điểm cẩn thận nhất:**

- **Kiểm tra chu trình trước transaction** (`_createsCycle`) — nếu để tới lúc
  ghi mới phát hiện thì đã xoá mất môn học rồi. Cạnh vừa thêm được cập nhật ngay
  vào bảng `parents` để tính đúng cho lần kiểm tra kế tiếp.
- **Cảnh báo file `.md` còn lại** — nếu không xoá file trong Vault, lần "Nạp vào
  CSDL" kế tiếp sẽ **dựng lại đúng môn vừa xoá**. Cảnh báo này được đưa vào
  `DeleteResult.warnings`.

---

## Trạng thái kiểm thử

```
flutter analyze  →  No issues found!
flutter test     →  57/57 All tests passed!
```

| File test | Số test | Phạm vi |
| --- | --- | --- |
| `test/graph_rag_test.dart` | 9 | `findSeeds` theo mã môn và theo từ khoá |
| `test/obsidian_parser_test.dart` | ~28 | Regex link/tag, front matter, `mergeMarkdown`, backlink index |
| `test/subject_delete_guard_test.dart` | ~20 | Phân loại rủi ro, nối tắt, chu trình, môn đơn độc |

Các ca đáng chú ý trong `graph_rag_test.dart`:

- Câu hỏi theo chủ đề viết tắt vẫn ra đúng môn
- Gõ không dấu vẫn khớp
- Khớp theo tên môn tiếng Anh và theo mô tả tiếng Việt
- Câu hỏi chung chung không suy ra môn nào (đi nhánh fallback)
- Không khớp bừa vào chuỗi con của từ khác

---

## Việc còn lại

1. **Popup cảnh báo xoá chưa có.** `lib/views/widgets/subject_detail_panel.dart:221`
   vẫn gọi thẳng `AppState.deleteSubject(id)` cũ với một hộp thoại chữ tĩnh, bỏ
   qua toàn bộ `SubjectDeleteGuard`. Cần widget hiển thị `DeleteImpact` (headline
   + details + chọn Cascade/Rewire + checkbox xoá file `.md`), rồi đổi
   `_confirmDelete` sang `analyzeDelete()` → popup → `deleteSubjectSafely()`.
2. **`buildBacklinkIndex()` / `buildTagIndex()` chưa có view nào dùng.**
3. **`flutter_markdown` đã bị discontinued**, khuyến nghị chuyển sang
   `flutter_markdown_plus`. Chưa gấp.
4. **Thiếu Android SDK** trên máy dev hiện tại — không ảnh hưởng target Windows.
