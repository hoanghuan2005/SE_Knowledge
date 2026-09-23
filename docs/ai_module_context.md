# Phân hệ AI — Bối cảnh, hiện trạng, đánh giá

> **Dự án:** SE Knowledge — bản đồ tri thức môn học FPTU-SE, desktop local-first
> **Phạm vi tài liệu:** toàn bộ phần AI (3 màn hình dùng AI + tầng dịch vụ phía sau)
> **Cập nhật:** 2026-09-23 · mọi con số trong file đều đo trên CSDL thật 64 môn / 47 dòng điểm

---

## 1. Vì sao cần phân hệ này

AI thương mại (ChatGPT, Gemini) không biết sinh viên đã học gì, điểm ra sao, chương trình FPTU ràng buộc thế nào. Hỏi *"em nên học gì tiếp"* thì nhận lời khuyên chung chung.

Phân hệ này giải quyết bằng cách **nạp đúng ngữ cảnh cá nhân vào prompt**, lấy từ ba nguồn có sẵn trong máy: đồ thị môn tiên quyết (SQLite), đề cương FAP/FLM, ghi chú `.md` trong Obsidian Vault, cộng bảng điểm nếu người dùng cho phép.

Ba ràng buộc thiết kế xuyên suốt:

| Ràng buộc | Cách đạt được |
|---|---|
| Không bịa | Prompt cấm nhắc môn ngoài dữ liệu được cấp; thiếu thì phải nói thẳng |
| Không nhồi nhét | Graph RAG trích subgraph thay vì gửi cả CSDL |
| Không phụ thuộc server | Gọi thẳng REST API nhà cung cấp, không có backend trung gian |

---

## 2. Ba màn hình dùng AI

```
                        AiService (cổng LLM duy nhất)
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌────────────────┐        ┌──────────────────┐       ┌────────────────────┐
│ Chat tổng quát │        │  Chat theo môn   │       │ Phân tích học lực  │
│ tab "Trợ lý AI"│        │ panel bên phải   │       │   tab "Học lực"    │
├────────────────┤        ├──────────────────┤       ├────────────────────┤
│ Graph RAG      │        │ extraContext     │       │ extraContext       │
│ trích subgraph │        │ 1 môn + đề cương │       │ hồ sơ học lực      │
│ từ câu hỏi     │        │ + ghi chú .md    │       │ tính thuần Dart    │
└────────────────┘        └──────────────────┘       └────────────────────┘
```

Cả ba đi qua **cùng một hàm** `AiService.ask()`, nên streaming, retry, dự phòng model, thông báo bị cắt đều áp dụng đồng nhất — sửa một chỗ là cả ba được.

### 2.1 Chat tổng quát

Đường dài nhất, dùng Graph RAG. Chi tiết ở mục 3.

**File:** `views/chat/ai_chat_page.dart`, `services/graph_rag_service.dart`, `services/chat_session_service.dart`

Có: streaming, link `[[MÃ MÔN]]` bấm được, panel minh bạch ngữ cảnh (số node/cạnh/token/ms), nút Sao chép, nút "Xem trên đồ thị", chỉ báo kết nối, nhiều đoạn chat lưu qua `SharedPreferences`.

### 2.2 Chat theo môn

**File:** `views/widgets/subject_chat_panel.dart`, `services/subject_chat_service.dart`

Không chạy Graph RAG. Ngữ cảnh khoanh đúng môn đang chọn, ghép từ:

1. Dữ liệu môn trong SQLite (mã, tên, kỳ, tín chỉ, mô tả)
2. Quan hệ đồ thị — tách bạch `PREREQUISITE` (bắt buộc) và `RELATED` (tham khảo)
3. Đề cương FAP đầy đủ, nếu môn đã nhập
4. Ghi chú `.md` người dùng tự viết, nếu đã export ra Vault

Khi có cả (3) và (4), prompt chèn thêm dòng dặn **lấy đề cương làm chuẩn** nếu ghi chú cá nhân mâu thuẫn, và phải nói cho người dùng biết chỗ lệch.

**Bốn câu hỏi gợi ý** tự sinh khi mở môn, cache theo môn trong RAM (mỗi môn gọi AI đúng 1 lần/phiên). Lời gọi này dùng đường riêng rẻ hơn — xem mục 4.

**Phiên chat giữ trong RAM** (`Map<subjectId, …>`), gồm cả phần chữ đang stream — chuyển sang môn khác rồi quay lại vẫn thấy đoạn đang chảy dở.

### 2.3 Phân tích học lực

**File:** `views/academic/academic_page.dart`, `services/academic_analytics_service.dart`

Điểm khác biệt: **phần lớn tính toán là Dart thuần, không nhờ AI**. AI chỉ nhận số liệu đã tính sẵn rồi diễn giải.

Tầng tính toán xác định:
- GPA tích luỹ có trọng số tín chỉ, học lại lấy lần qua môn mới nhất
- Loại môn điều kiện tốt nghiệp khỏi GPA
- Xu hướng 3 kỳ gần nhất (`bySemester.sublist(length - 3)`)
- Phân nhóm năng lực theo tiền tố mã môn (`domainByPrefix`)
- Rủi ro trên đồ thị: `score = (7.0 - grade) × (1 + số môn phụ thuộc)` — môn nền điểm thấp mà mở ra càng nhiều môn sau thì xếp càng cao

AI nhận câu hỏi cố định 4 phần (điểm mạnh / điểm yếu / môn sắp học có rủi ro / kế hoạch kỳ tới) kèm bộ quy tắc riêng: phải dẫn mã môn và điểm thật, **chỉ kết luận nhóm năng lực khi có ≥3 môn đã có điểm**, không suy diễn từ môn chưa học.

**Nhận xét được cache theo dấu vân tay dữ liệu.** Đây là lời gọi nặng nhất trong app — gửi cả hồ sơ học lực, kế hoạch mục tiêu, danh sách môn lập trình và các vị trí combo. Mở lại tab mà số liệu chưa đổi thì hiện luôn bản đã lưu, kèm dòng nói rõ đó là bản cũ và nút *"Phân tích lại"*.

Vân tay gồm **cả kích thước đồ thị**, không riêng bảng điểm: sửa môn hay sửa quan hệ tiên quyết cũng làm phần nhận xét rủi ro lộ trình khác đi. Cache tách theo từng câu hỏi vì trang có nhiều nút hỏi.

---

## 3. Graph RAG — cách chọn ngữ cảnh

Đây là phần nhiều logic nhất. Mục tiêu: từ câu hỏi tiếng Việt, tìm đúng vài môn liên quan thay vì gửi cả 64 môn.

### 3.1 Các bước

```
Câu hỏi
  │
  ├─ 1. Bắt mã môn viết đầy đủ:  \b[A-Z]{2,4}\d{2,4}[A-Z]?\b
  │     → "PRJ301" ⇒ chắc chắn, luôn đủ tin
  │
  ├─ 2. Câu hỏi toàn cục? ("lộ trình", "kỳ tới", "tốt nghiệp"…)
  │     → dùng TOÀN đồ thị, bỏ qua bước 3-4
  │
  ├─ 3. Tách khái niệm
  │     • bỏ dấu tiếng Việt, tách từ
  │     • lọc 91 stopword
  │     • cụm 2 từ liền nhau (vì bỏ dấu xong "đồ"/"đó" đều thành "do")
  │     • bảng viết tắt: AI → artificial intelligence, CSDL → database…
  │       (viết tắt 2 chữ chỉ bung khi gõ HOA: "hướng AI" ✓, "Ai là ai" ✗)
  │
  ├─ 4. Đo độ phổ biến từng khái niệm trong danh mục
  │     • khớp >25% số môn  → vứt (không phân biệt được gì)
  │     • khớp ≤2 môn       → "đặc hiệu", đủ tin để đính đề cương
  │
  ├─ 5. Chấm điểm từng môn
  │     mã môn 4đ  >  tên môn 2đ  >  mô tả 1đ
  │     giữ môn ≥ 2/3 điểm cao nhất, tối đa 5 hạt giống
  │     hoà điểm → xếp theo mã môn (kết quả ổn định)
  │     nếu câu hỏi ĐÃ có mã môn đầy đủ → chỉ nhận thêm môn khớp chắc chắn
  │
  ├─ 6. BFS 2 chiều, 2 bước từ hạt giống
  │     trần 24 node (20 nếu có kèm điểm)
  │
  └─ 7. Dựng prompt
        • mỗi môn: mã, tên, kỳ, tín chỉ, tiên quyết, mô tả (≤160 ký tự)
        • + điểm của sinh viên nếu bật công tắc
        • + đề cương ĐẦY ĐỦ cho tối đa 2 môn đủ tin
        • + cảnh báo nếu viết tắt trỏ vào nhiều môn (mục 3.3)
```

### 3.2 Vì sao mã môn nặng hơn tên môn

Người dùng hay viết tắt mã (`csd`, `swr`, `prf`). Trước đây mã và tên tính điểm ngang nhau, nên câu *"điểm trung bình csd và swr của tôi là bao nhiêu"* mất hẳn `SWR302`: bốn môn tình cờ có chữ "trung" trong tên hoà điểm rồi chen chỗ, mà chỉ giữ 5 hạt giống.

Sau khi tách thang điểm và bổ sung *điểm/trung/bình* vào stopword:

| | Trước | Sau |
|---|---|---|
| Hạt giống | JPD133, JPD316, VOV114, OTP101, CSD201 | **CSD201, SWR302** |
| Node | 20 | 14 |

### 3.3 Đã gọi tên bằng mã thì không nhận thêm môn khớp mờ

Câu *"prj301 và swd392 liên quan gì nhau"* từng kéo theo `GRC490`, `JPD316`, `JPD133` — chỉ vì mấy chữ còn lại trong câu trùng vài từ trong phần mô tả của chúng.

Khi câu hỏi **đã có mã môn viết đầy đủ**, người dùng biết rõ mình hỏi gì, nên chỉ nhận thêm môn khớp vào **mã hoặc tên** — bỏ những môn chỉ trùng ở mô tả:

| Câu hỏi | Trước | Sau |
|---|---|---|
| `prj301 và swd392 liên quan gì nhau` | +GRC490, JPD316, JPD133 | **chỉ PRJ301/SWD392** |
| `prj301 và các môn database` | — | **PRJ301/DBI202** |

Ca thứ hai là lý do **không** cắt thô bạo toàn bộ bước tìm theo từ khoá: câu hỏi trộn mã môn với chủ đề vẫn phải chạy, vì `database` khớp thẳng vào tên `Database Systems`.

### 3.4 Viết tắt trỏ vào nhiều môn

Gõ `jpd` khớp cả `JPD113/123/133/316/326`. App **không đoán**: không đính đề cương môn nào, và chèn vào prompt lời dặn **hỏi lại người dùng muốn môn nào**.

Điều kiện kích hoạt hẹp — đủ cả ba mới tính:
1. Khớp qua **mã môn** (gõ tên chủ đề như "software" là hỏi rộng thật, hỏi lại chỉ làm phiền)
2. **Không môn nào** đủ tin
3. **Từ 2 môn** trở lên

Kiểm chứng trên dữ liệu thật:

| Câu hỏi | Hỏi lại? |
|---|---|
| `môn jpd học gì` | **CÓ** — 5 môn JPD |
| `môn prf học gì` | không — rõ 1 môn |
| `điểm trung bình csd và swr` | không — rõ 2 môn |
| `học về software thì sao` | không — hỏi rộng theo chủ đề |
| `gợi ý lộ trình học` | không — toàn cục |

### 3.5 Bảng điểm trong ngữ cảnh

Chỉ gửi khi công tắc *"Gửi bảng điểm kèm câu hỏi"* trong Cài đặt còn bật — kiểm tra ngay tại nguồn, không chỉ ẩn nút ở UI.

Độ chính xác đo trên dữ liệu thật:

| Chỉ số | Kết quả |
|---|---|
| Dòng điểm / mã môn riêng biệt | 47 / 47 |
| **Khớp với môn trong đồ thị** | **47/47** |
| Có điểm nhưng không có môn | 0 |
| GPA · tín chỉ · môn tính GPA | 7.96 · 90 · 29 — khớp tab Học lực |

Khớp theo mã môn viết hoa ở cả hai đầu. Học lại lấy bản ghi đã qua, kỳ gần nhất.

**Điểm của môn không lọt vào subgraph vẫn được gửi**, dạng một dòng gọn:

```
Điểm các môn đã học khác, không nằm trong danh sách chi tiết bên dưới
(27 môn): DBI202 7.0, JPD113 8.5, MAE101 7.9, ...
```

Subgraph bị cắt ở 20 node khi có kèm điểm, trong khi sinh viên có thể đã học 47 môn. Thiếu dòng này thì câu hỏi so sánh (*"môn nào tôi thấp nhất"*) bị trả lời dựa trên đúng phần AI nhìn thấy, mà AI không hề biết mình đang nhìn thiếu. Dạng `MÃ ĐIỂM` rẻ hơn nhiều so với nâng trần node, vì mỗi node còn kéo theo mô tả và quan hệ tiên quyết.

Chỉ chèn ở nhánh không-fallback (nhánh fallback vốn đã liệt kê hết môn) và loại những môn đã hiện chi tiết, để không lặp.

---

## 4. Phân tầng model

Google tính hạn mức **RPM/TPM/RPD riêng cho từng model**. Đây là lý do phân tầng, không phải tiền — sau các lần cắt, lời gọi phụ chỉ còn ~292 token, rẻ tới mức không đáng bàn.

### 4.1 Model phụ cho tác vụ nền

Việc sinh 4 câu hỏi gợi ý đi sang model riêng (`preferLightModel`), chọn từ **dropdown cố định** trong Cài đặt — không cho gõ tay để khỏi sai tên model.

Danh sách lấy từ trang model chính thức, chỉ giữ nhóm sinh văn bản (bỏ TTS, Live, Transcribe, image, và các bản Pro vì đắt hơn model chính):

```
gemini-3.5-flash-lite · gemini-3.1-flash-lite · gemini-2.5-flash-lite
gemini-3.5-flash      · gemini-2.5-flash
```

OpenAI để trống vì chưa có ID đã kiểm chứng.

Chọn sai cũng không mất tính năng: 404/400 → lùi về model chính ngay trong lượt đó, và ngừng thử model phụ cả phiên.

**Đã xác nhận chạy**: biểu đồ *Requests per model* tách hai đường — `Gemini 3.6 Flash` 14 lượt (chat), `Gemini 3.1 Flash Lite` 1 lượt (gợi ý).

### 4.2 Model dự phòng khi quá tải

Hoàn toàn **tự động, không cấu hình**: 503 ập tới giữa buổi demo thì không ai kịp vào Cài đặt.

```
model chính → 503 → thử lại 0.8s → 2s → vẫn hỏng
  → gemini-3.5-flash  → 404 (key không có quyền)? đi tiếp
  → gemini-2.5-flash  → OK → trả lời + ghi chú model nào đã viết
  → hết ứng viên      → ném lại lỗi 503 gốc
```

Cố ý **không** dùng chung ô "model tác vụ phụ": ô đó chọn theo rẻ/nhanh, còn chỗ này thay model chính trả lời người dùng nên cần model mạnh. Danh sách dự phòng xếp Flash đầy đủ trước Flash-Lite.

Chỉ đổi model với lỗi quá tải (429/5xx). Sai key, request hỏng, sai tên model thì đổi cũng vô ích.

**Luôn ghi rõ model nào đã trả lời** — im lặng còn tệ hơn báo lỗi, vì người dùng sẽ tưởng model mình chọn viết dở.

---

## 5. Tầng gọi LLM

### 5.1 Streaming

Đọc Server-Sent Events, chữ hiện dần. Ba lỗi từng gặp và cách xử lý:

| Lỗi | Nguyên nhân | Cách sửa |
|---|---|---|
| Chữ lộn xộn / "nội dung rỗng" | Giả định mỗi sự kiện SSE gọn 1 dòng, nhưng Gemini đôi khi trải JSON nhiều dòng → dòng sau bị bỏ, JSON cụt, decode fail âm thầm | `sseEventPayloads()` gom theo sự kiện, dòng trống mới là ranh giới |
| Tiếng Anh lẫn giữa câu Việt | Ghép cả `parts` gắn cờ `thought: true` — đó là nháp suy nghĩ nội bộ của model | `geminiVisibleText()` lọc bỏ |
| Câu trả lời đứt ngang | `maxOutputTokens` 1024, mà phần nháp cũng ăn vào hạn mức | Nâng 4096 + đọc `finishReason`, bị cắt thì nói thẳng |

### 5.2 Các tham số

| Hằng số | Giá trị | Ý nghĩa |
|---|---|---|
| `timeout` | 45s | Khoảng chờ **giữa hai chunk**, không phải tổng — câu dài không bị cắt oan |
| `maxOutputTokens` | 4096 | |
| `maxHistoryMessages` | 8 | Chỉ gửi lại 8 tin gần nhất, **lọc bỏ tin báo lỗi cũ** |
| `maxRetryAttempts` | 2 | Giãn 0.8s → 2s |

### 5.3 Prompt

Hai bộ, chọn theo việc:

**Prompt gia sư** (~380 token) — cho ba màn hình trả lời. Quy tắc chính:
- Viết tiếng Việt, ngắn gọn
- Mã môn bọc `[[...]]` để UI biến thành link — **chỉ mã môn có thật**
- Lộ trình phải đánh số theo thứ tự học, nêu lý do theo quan hệ tiên quyết
- Dữ liệu được cấp là nguồn **duy nhất** cho mọi khẳng định về chương trình
- Được khuyên kỹ năng/công cụ **ngoài** chương trình, nhưng phải ghi rõ là phần tự học
- Chương trình thiếu môn cho chủ đề được hỏi → nói thẳng trước, rồi mới gợi ý

Thêm bộ quy tắc học lực khi ngữ cảnh có điểm (~225 token).

**Prompt tối giản** (~84 token) — chỉ cho việc sinh gợi ý. Giữ đúng 2 quy tắc có tác dụng (tiếng Việt ngắn gọn, không bịa môn), bỏ hết phần còn lại. Bỏ luôn quy tắc `[[...]]` vì chip gợi ý là nhãn nút chữ thuần, để lại thì hiện `[[JPD113]]` lù lù.

---

## 6. Chi phí — đo thật

### Lời gọi sinh gợi ý (mỗi môn, 1 lần/phiên)

| Giai đoạn | Token |
|---|---|
| Ban đầu | ~2500 |
| Sau khi cắt ngữ cảnh (đề cương → bản rút gọn) | ~590 |
| Sau khi cắt prompt (gia sư → tối giản) | **~292** |

Bản rút gọn đề cương đo trên 3 môn thật: `PRF192` 1675→148, `MAD101` 2294→149, `CSD201` 2555→147 token (giảm ~92%). Vẫn giữ mô tả môn, bảng đầu điểm, số CLO, số buổi — đủ để đặt câu hỏi cụ thể như *"Progress test chiếm bao nhiêu %"*.

### Chat tổng quát

Câu *"tôi muốn làm AI Engineer nên học gì"*: **~4610 → ~866 token**, nhờ không còn đính đề cương cho những môn khớp mơ hồ.

---

## 7. Kiểm thử

| File | Số test | Phủ gì |
|---|---|---|
| `graph_rag_test.dart` | 32 | Chọn hạt giống, lọc từ phổ thông, mức tin cậy, viết tắt mã môn, hỏi lại khi mơ hồ, đề cương rút gọn |
| `sse_event_test.dart` | 21 | Gom sự kiện SSE, lọc `thought`, `finishReason`, phân loại lỗi tạm thời, xếp hàng model dự phòng |
| `suggestion_lines_test.dart` | 6 | Làm sạch 4 câu gợi ý |
| `academic_ai_cache_test.dart` | 6 | Cache nhận xét học lực, bỏ cache khi dữ liệu đổi, chịu được dữ liệu lưu hỏng |
| **Tổng phần AI** | **65** | |

Toàn dự án: **328 test — 325 pass / 3 fail**. Ba lỗi đều thuộc nhóm bảng điểm (`academic_analytics`, `transcript_db`, `transcript_parser`), nguyên nhân chung là thiếu file `test/fixtures/transcript/StudentTranscript_SE193040.xls`. **Không thuộc phân hệ AI.**

`flutter analyze`: sạch.

Nguyên tắc khi viết test: mọi logic quyết định được tách thành **hàm thuần** để test không cần mạng hay DB — `sseEventPayloads`, `geminiVisibleText`, `isTransientAiStatus`, `fallbackModelOrder`, `ambiguousCodeMatches`, `findSeeds`, `cleanSuggestionLines`.

---

## 8. Thiếu sót & rủi ro còn lại

### 8.1 Giới hạn thiết kế đã biết

**Ngữ cảnh chi tiết vẫn cắt ở 20 môn khi có điểm.** Điểm của những môn bị cắt nay đã được gửi kèm dạng dòng gọn (mục 3.5), nên câu hỏi so sánh trả lời đúng được. Nhưng phần **mô tả, quan hệ tiên quyết, đề cương** của chúng thì vẫn không có — hỏi sâu về một môn nằm ngoài subgraph thì AI chỉ biết mỗi điểm số.

**Streaming chỉ chạy thật trên Desktop.** `package:http` trên web dùng `BrowserClient` gom trọn response rồi mới trả, nên `response.stream` chỉ phát một lần ở cuối. Hiện chưa phải vấn đề vì app chốt là desktop (SQLite FFI + `path_provider` vốn không chạy web), chỉ thành vấn đề nếu nhóm quay lại làm bản Web.

**Chọn hạt giống vẫn còn nhiễu ở câu hỏi không có mã môn.** Bước lọc mới chỉ áp dụng khi câu hỏi đã ghi rõ mã (mục 3.3). Câu hỏi thuần chủ đề vẫn có thể kéo vài môn khớp mờ — chúng không đủ tin nên không tốn đề cương, chỉ thêm vài dòng.

### 8.2 Nợ cấu trúc

- `_composeContext()` — logic dựng prompt cho chat theo môn — vẫn nằm trong widget `SubjectChatPanel`, đáng lẽ thuộc tầng service.
- Câu hỏi 4 phần của màn Học lực (`_analysisQuestion`) nằm trong `AcademicPage`.

Cả hai đều thuần chuyện sắp xếp code, không đổi gì với người dùng, và có rủi ro làm gãy thứ đang chạy tốt. Đáng làm nếu được chấm điểm kiến trúc, không đáng nếu sắp hết thời gian.

### 8.3 Ngoài phân hệ AI nhưng ảnh hưởng trực tiếp

- **CSDL không có môn AI nào.** `artificial intelligence` khớp 0/64 môn. Mọi câu hỏi định hướng AI đều phải trả lời "chương trình không có môn này" — đúng nhưng nghèo. Thuộc khâu nhập dữ liệu FAP.
- **Rác trong danh mục môn**: có mục tên `CURRICULUM DETAILS BIT_IS_K20D` bị coi là một môn học và lọt vào ngữ cảnh gửi AI.
- **3 test đỏ** vì thiếu file fixture bảng điểm.
- **`_switchProvider` biến mất** khỏi trang Cài đặt: đổi tab Gemini ↔ OpenAI không nạp lại API key tương ứng.

---

## 9. Đánh giá tổng thể

**Đã hoàn thành** toàn bộ hạng mục được giao trong đề bài: Gemini Streaming API, Graph-RAG Pipeline, Prompt Tutor, Citation Linker, cùng ba sản phẩm bàn giao `GeminiClient` / `GraphRAGService` / prompt học tập kèm link `[[note]]`.

**Điểm mạnh nhất** không nằm ở số tính năng mà ở chỗ mọi quyết định đều **đo được và có test khoá lại**: 4610→866 token cho chat tổng quát, 2500→292 cho lời gọi phụ, 47/47 dòng điểm khớp đúng, ba lỗi streaming tìm ra bằng cách đo trên dữ liệu thật chứ không đoán.

**Rủi ro còn lại đã thu hẹp đáng kể.** Ba màn hình đều đã chạy thử với API thật. Thứ duy nhất chưa chứng minh được bằng thực nghiệm là **đường dự phòng model** — nó chỉ kích hoạt khi nhà cung cấp trả 503 thật, không tạo ra chủ động được; logic có test nhưng đường end-to-end chưa từng thực thi.

Những gì còn lại trong mục 8 đều **không chặn việc nộp bài**: giới hạn thiết kế đã được ghi rõ và có cách giảm nhẹ, nợ cấu trúc thuần chuyện sắp xếp code, còn bốn mục ở 8.3 nằm ngoài phân hệ AI và cần người phụ trách phần đó xử lý.
