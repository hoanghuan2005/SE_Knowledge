# FPTU SE Knowledge with Obsidian Second Brain

Tổng quan dự án, các chức năng hiện có và cách chúng vận hành.

- [1. Dự án là gì](#1-dự-án-là-gì)
- [2. Bài toán muốn giải](#2-bài-toán-muốn-giải)
- [3. Kiến trúc tổng thể](#3-kiến-trúc-tổng-thể)
- [4. Mô hình dữ liệu](#4-mô-hình-dữ-liệu)
- [5. Các chức năng hiện có](#5-các-chức-năng-hiện-có)
- [6. Các luồng hoạt động chính](#6-các-luồng-hoạt-động-chính)
- [7. Những chỗ chống mất dữ liệu](#7-những-chỗ-chống-mất-dữ-liệu)
- [8. Trạng thái hiện tại](#8-trạng-thái-hiện-tại)

---

## 1. Dự án là gì

**SE Knowledge** là ứng dụng desktop giúp sinh viên ngành Kỹ thuật phần mềm
FPTU dựng **bản đồ tri thức môn học** của riêng mình: mỗi môn là một node, mỗi
quan hệ tiên quyết là một cạnh có hướng, và toàn bộ ghi chú học tập sống song
song trong một **Obsidian Vault** dưới dạng file `.md` thuần.

Ba mảnh ghép của hệ thống:

| Mảnh | Vai trò |
| --- | --- |
| **SQLite** | Nguồn sự thật của *cấu trúc*: môn học và quan hệ tiên quyết |
| **Obsidian Vault** | Nguồn sự thật của *nội dung*: ghi chú, tài liệu, bài tập |
| **Trợ lý AI** | Đọc đồ thị để tư vấn lộ trình học, có trích dẫn bấm được |

Hai chiều dữ liệu đi qua lại được: **Export** ghi đồ thị ra file `.md`, **Import**
đọc ngược file `.md` về SQLite. Người dùng có thể sửa ghi chú trong chính
Obsidian rồi nạp lại vào app, hoặc ngược lại.

**Công nghệ:** Flutter Desktop (Dart thuần), SQLite nhúng qua
`sqflite_common_ffi`, `dart:io` để đọc ghi Vault, `graphview` cho phần vẽ, `http`
gọi thẳng REST API Gemini/OpenAI, `shared_preferences` lưu cấu hình.

Không có server, không có Docker, không có tài khoản đăng nhập. Mạng chỉ được
dùng đúng một chỗ: khi người dùng chủ động chat với AI.

## 2. Bài toán muốn giải

Sinh viên FPTU đối mặt với ba vấn đề khi lập kế hoạch học:

1. **Quan hệ tiên quyết nằm rải rác** trong syllabus dạng bảng, khó thấy được
   "học môn này thì mở ra những môn nào".
2. **Ghi chú và cấu trúc chương trình tách rời nhau.** Obsidian rất mạnh cho
   ghi chú nhưng không hiểu khái niệm "môn tiên quyết"; bảng syllabus thì không
   chứa được ghi chú.
3. **Hỏi ChatGPT thì nó không biết mình đã học gì**, trả lời chung chung theo
   kiến thức huấn luyện chứ không theo lộ trình thật của người hỏi.

SE Knowledge giải quyết bằng cách đặt đồ thị tiên quyết làm trung tâm: giao diện
vẽ nó ra, Vault ghi nó thành file, và AI đọc chính nó để trả lời.

## 3. Kiến trúc tổng thể

```
                      ┌────────────────────────────┐
                      │      Giao diện Flutter     │
                      │  5 tab: Graph · Môn học ·  │
                      │   Vault · AI · Cài đặt     │
                      └─────────────┬──────────────┘
                                    │
                      ┌─────────────▼──────────────┐
                      │         AppState           │
                      │ ChangeNotifier giữ graph,  │
                      │  môn đang chọn, tab ghi chú│
                      └──┬────────┬────────┬───────┘
                         │        │        │
         ┌───────────────▼──┐  ┌──▼──────┐ │  ┌──────────────────┐
         │    DbService     │  │Obsidian │ │  │   AiService      │
         │  SQLite (ffi)    │  │Service  │ │  │  SSE streaming   │
         └───────┬──────────┘  └────┬────┘ │  └────────┬─────────┘
                 │                  │      │           │
                 │         ┌────────▼──────▼──┐  ┌─────▼──────────┐
                 │         │  MarkdownParser  │  │ GraphRagService│
                 │         │  (thuần Dart)    │  │  trích subgraph│
                 │         └────────┬─────────┘  └─────┬──────────┘
                 │                  │                  │
         ┌───────▼────────┐   ┌─────▼──────┐    ┌──────▼─────────┐
         │ se_knowledge   │   │  Obsidian  │    │ Gemini /OpenAI │
         │    .db         │   │   Vault    │    │   REST API     │
         │  (1 file)      │   │  (*.md)    │    │   (chỉ khi chat)│
         └────────────────┘   └────────────┘    └────────────────┘
```

**Nguyên tắc phân tầng:** toàn bộ logic regex nằm **duy nhất** trong
`MarkdownParser` — file thuần Dart, không `dart:io`, không SQLite, không Flutter.
Nhờ vậy nó chạy được bằng `flutter test` mà không cần Visual Studio, và mọi tầng
khác (ObsidianService khi quét Vault, giao diện chat khi bóc trích dẫn) đều gọi
chung một bộ regex thay vì mỗi nơi viết một kiểu.

## 4. Mô hình dữ liệu

Hai bảng, một file `.db` duy nhất:

```sql
CREATE TABLE subjects (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT    NOT NULL UNIQUE,   -- PRF192, CSD201...
  name        TEXT    NOT NULL,
  semester    INTEGER NOT NULL DEFAULT 1,
  credits     INTEGER NOT NULL DEFAULT 3,
  description TEXT    NOT NULL DEFAULT '',
  note_path   TEXT,                      -- trỏ tới file .md trong Vault
  created_at  TEXT    NOT NULL,
  updated_at  TEXT    NOT NULL
);

CREATE TABLE prerequisites (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  subject_id      INTEGER NOT NULL,      -- môn cần điều kiện
  prerequisite_id INTEGER NOT NULL,      -- môn phải học trước
  relation_type   TEXT    NOT NULL DEFAULT 'PREREQUISITE',
  UNIQUE (subject_id, prerequisite_id),
  CHECK (subject_id <> prerequisite_id),
  FOREIGN KEY (subject_id)      REFERENCES subjects (id) ON DELETE CASCADE,
  FOREIGN KEY (prerequisite_id) REFERENCES subjects (id) ON DELETE CASCADE
);
```

Ràng buộc được đẩy xuống tận schema: `UNIQUE` chặn cạnh trùng, `CHECK` chặn môn
tự trỏ chính nó, `ON DELETE CASCADE` dọn cạnh mồ côi. Ba index phủ hai chiều
duyệt đồ thị và cột `semester`.

Hai loại quan hệ: `PREREQUISITE` (tiên quyết bắt buộc) và `RELATED` (liên quan /
tham khảo).

**Dữ liệu mẫu** được seed sẵn lúc tạo database: 7 môn (PRF192, MAD101, CSD201,
DBI202, PRJ301, PRM393, SWR302) và 7 liên kết, đủ để mở app lên là thấy ngay một
đồ thị có hình thù.

## 5. Các chức năng hiện có

App chia thành 5 tab trên thanh ribbon bên trái, kiểu Obsidian.

### 5.1. Graph view — đồ thị tri thức

- Vẽ toàn bộ môn học thành node, quan hệ tiên quyết thành cạnh có hướng.
- **Node kéo thả được**, canvas cuộn để zoom và kéo để di chuyển
  (`InteractiveViewer`), có nút về mức zoom mặc định.
- **Lọc theo học kỳ** — chọn một kỳ thì chỉ hiện môn của kỳ đó.
- **Màu node theo học kỳ**, có chú giải ở góc.
- Bấm vào node thì bảng chi tiết bên phải mở ra: thông tin môn, danh sách môn
  tiên quyết, danh sách môn mà nó mở ra, và ghi chú `.md` gắn kèm.

### 5.2. Danh sách môn học — CRUD

- Bảng liệt kê toàn bộ môn, **tìm kiếm** theo mã / tên / mô tả.
- **Thêm / sửa / xoá** môn qua form: mã, tên, học kỳ, số tín chỉ, mô tả.
- **Chọn nhiều môn tiên quyết ngay trong form** bằng dãy chip bấm chọn; lúc lưu
  app tự tính chênh lệch và chỉ thêm/gỡ đúng những cạnh thay đổi.
- **Thêm liên kết riêng lẻ** qua `AddEdgeDialog`, chọn được loại quan hệ
  (tiên quyết bắt buộc / liên quan tham khảo).
- **Gợi ý thứ tự học** — sắp xếp topo bằng thuật toán Kahn, ưu tiên học kỳ nhỏ
  trước rồi tới mã môn. Đồ thị còn chu trình thì trả về `null` và app báo là
  không xếp được thay vì đưa ra một thứ tự sai.

### 5.3. Obsidian Vault

- **Chọn thư mục Vault** bằng hộp thoại hệ thống (`file_selector`).
- **Quét lại** — đọc mọi file `.md` trong Vault, bóc front matter, wiki link và
  hashtag, hiện danh sách kèm xem trước nội dung.
- **Ghi ra Vault (Export)** — xuất toàn bộ môn học thành file `.md`.
- **Nạp vào CSDL (Import)** — đọc ngược file `.md` về SQLite.

### 5.4. Trợ lý học tập AI

- **Nhiều phiên chat**, quản lý ở thanh bên: tạo mới, đổi tên, xoá, tìm kiếm.
  Lịch sử lưu trong `shared_preferences`, mở lại app vẫn còn.
- **Trả lời hiện dần theo dòng chảy (SSE streaming)** thay vì đứng im chờ.
- **Graph RAG** — trước mỗi câu hỏi, app trích ra phần đồ thị liên quan trực
  tiếp rồi mới gửi đi, thay vì nhồi cả cơ sở dữ liệu vào prompt.
- **Khung ngữ cảnh xổ được** dưới mỗi câu trả lời, cho biết chính xác app đã gửi
  gì: mã môn khớp được, số node, số cạnh, token ước lượng, thời gian trích.
- **Trích dẫn bấm được** — mỗi mã môn AI nhắc tới thành một liên kết, bấm vào mở
  thẳng tab ghi chú của môn đó.
- Nút **Xem trên đồ thị** nhảy sang tab Graph với node đã được chọn sẵn, và nút
  **Sao chép** câu trả lời.
- Hỗ trợ hai nhà cung cấp: **Google Gemini** và **OpenAI**.

### 5.5. Trình soạn ghi chú Markdown

- Mở theo tab, ngay trong app, không cần chuyển sang Obsidian.
- Hai chế độ: **soạn thảo** và **xem trước** đã render.
- Thanh công cụ chèn nhanh cú pháp: heading, in đậm, in nghiêng, code, khối
  code, trích dẫn, gạch đầu dòng, checkbox, đường kẻ ngang, và **wiki link
  `[[...]]`**.
- `Ctrl+S` để lưu xuống file `.md`.

### 5.6. Cài đặt

- **Đổi giao diện Tối / Sáng**, lưu lại cho lần mở sau (cũng có nút bật nhanh
  trên ribbon).
- **Chọn nhà cung cấp AI**, nhập API key và tên model. Mỗi nhà cung cấp có ô
  lưu riêng nên đổi qua lại không ghi đè key của nhau.
- **Thông tin lưu trữ**: đường dẫn file `.db`, dung lượng, đường dẫn Vault, và
  thống kê nhanh — bao nhiêu môn, bao nhiêu liên kết, bao nhiêu môn rời rạc.
- **Xoá toàn bộ dữ liệu** trong SQLite để demo lại từ đầu.

## 6. Các luồng hoạt động chính

### 6.1. Khởi động

```
main()
 ├─ DbService.registerFfi()        đăng ký SQLite FFI cho desktop
 ├─ SettingsService.init()         nạp cấu hình + di chuyển key AI bản cũ
 ├─ ChatSessionService.init()      nạp lịch sử chat
 └─ AppState.bootstrap()           mở .db (tạo + seed nếu lần đầu), nạp đồ thị
```

`AppState` là một `ChangeNotifier` duy nhất giữ `GraphData` trong bộ nhớ. Mọi
thao tác ghi đều kết thúc bằng `refresh()` — đọc lại đồ thị rồi thông báo, nên
đồ thị, bảng danh sách và bảng chi tiết luôn khớp nhau mà không cần tự đồng bộ
từng chỗ.

### 6.2. Export — từ SQLite ra Vault

```
exportAll(vaultPath)
 └─ với mỗi môn:
     ├─ file chưa tồn tại  →  buildMarkdown()   sinh mới từ đầu
     └─ file đã tồn tại    →  mergeMarkdown()   chỉ cập nhật phần app sở hữu
 └─ ghi thêm _INDEX.md     bảng tổng hợp toàn bộ môn, nhóm theo học kỳ
```

File `.md` sinh ra có dạng:

```markdown
---
code: CSD201
name: Data Structures and Algorithms
semester: 2
credits: 3
tags: [subject, semester-2]
---

# CSD201 — Data Structures and Algorithms

Mô tả môn học...

## Môn tiên quyết
- [[PRF192]]
- [[MAD101]]

## Mở ra các môn
- [[PRJ301]]

## Ghi chú
```

**Điểm quan trọng của `mergeMarkdown`:** app chỉ sở hữu đúng ba khối — front
matter, mục "Môn tiên quyết", mục "Mở ra các môn". Mọi heading khác người dùng
tự thêm ("Tài liệu", "Bài tập", "Đề thi") được giữ nguyên từng dòng. Export lại
nhiều lần vẫn cho cùng một kết quả, không ăn mất ghi chú.

### 6.3. Import — từ Vault về SQLite

```
planImport(vaultPath)          chỉ đọc, chưa ghi gì
 ├─ scanVault()                dart:io quét mọi file .md
 ├─ MarkdownParser.parse()     bóc front matter, [[link]], #tag
 └─ đối chiếu với SQLite  →  VaultSyncPlan
                               ├─ môn cần thêm
                               ├─ môn cần cập nhật
                               ├─ cạnh cần thêm
                               └─ cạnh cần gỡ
       ↓  người dùng xem trước rồi mới xác nhận
applyPlan(plan)               ghi xuống, trả về VaultSyncReport
```

Tách làm hai bước để không bao giờ ghi mù vào cơ sở dữ liệu: người dùng thấy
trước chính xác cái gì sắp đổi.

Cách app hiểu một file `.md`:

- **Front matter** cho mã môn, tên, học kỳ, số tín chỉ, tag.
- **Wiki link nằm dưới heading "Môn tiên quyết"** trở thành cạnh tiên quyết —
  đây là lý do parser phải biết mỗi link nằm dưới heading nào, chứ không chỉ
  biết nó tồn tại.
- Link nằm trong khối code, code inline hoặc URL bị bỏ qua.
- Hashtag `#tag` được gom lại (hỗ trợ tag lồng `#a/b/c` và chữ có dấu tiếng
  Việt), nhưng `## Heading` và `#1` thì không bị nhận nhầm.

### 6.4. Hỏi AI — Graph RAG + streaming

```
Người dùng gõ câu hỏi
        │
        ▼
GraphRagService.buildContext(question)
 ├─ findSeeds()   ① mã môn viết thẳng trong câu ("PRJ301")
 │                ② từ khoá đối chiếu mã / tên / mô tả
 │                   · bỏ dấu tiếng Việt
 │                   · bảng viết tắt: AI → artificial intelligence...
 │                   · lọc stopword tiếng Việt
 ├─ _expand()     BFS 2 chiều, 2 bước, trần 24 node
 └─ _renderPrompt()
        │  (không suy ra được môn nào → fallback: gửi toàn bộ đồ thị)
        ▼
 onContext()  →  khung "Graph RAG" hiện lên ngay, trước cả chữ đầu tiên
        │
        ▼
AiService.ask()  →  SSE tới Gemini hoặc OpenAI
        │
        ▼
 onDelta()  →  chữ hiện dần từng mẩu
        │
        ▼
Câu trả lời + GraphRagSummary lưu kèm tin nhắn
        │
        ▼
_LinkedAnswerText bóc [[CSD201]] thành link bấm được
```

System prompt ép AI viết mã môn trong `[[...]]` — đây chính là điều kiện để tầng
giao diện biến chúng thành liên kết. Prompt còn cấm bịa môn không có trong danh
sách được cung cấp, và yêu cầu nói thẳng khi dữ liệu không đủ.

Chỉ 8 tin nhắn gần nhất được gửi kèm, và các tin báo lỗi cũ bị lọc ra — nếu gửi
trọn lịch sử thì càng chat lâu prompt càng phình, đi ngược lại chính mục tiêu
tiết kiệm token của Graph RAG.

### 6.5. Xoá môn học — kiểm tra ràng buộc trước

Đây là luồng được làm cẩn thận nhất, vì `ON DELETE CASCADE` xoá sạch cạnh liên
quan mà không báo một tiếng nào. Xoá một môn nằm giữa chuỗi `A → B → C` là cắt
đôi lộ trình học và không có cách nào hoàn tác.

```
Bấm nút xoá
     ▼
SubjectDeleteGuard.analyze()        chỉ đọc, chưa ghi gì
     ├─ môn nào đang phụ thuộc vào nó?        → mức NGUY HIỂM
     ├─ môn nào nó đang lấy làm tiên quyết?   → mức CẦN CÂN NHẮC
     ├─ môn nào sẽ thành node đơn độc?
     ├─ nối tắt được những cạnh nào?  A → C
     └─ cạnh nối tắt nào sẽ tạo chu trình?    → loại sẵn, kèm lý do
     ▼
Hộp thoại cảnh báo — nội dung đổi theo từng môn
     ├─ banner đổi màu theo mức rủi ro
     ├─ liệt kê từng nhóm môn bị ảnh hưởng
     ├─ chọn: Nối tắt  ↔  Xoá thẳng
     └─ tuỳ chọn xoá luôn file .md trong Vault
     ▼
deleteSubjectSafely()               một transaction duy nhất
```

Hai chi tiết đáng chú ý:

- **Kiểm tra chu trình xảy ra trước transaction.** Nếu để tới lúc ghi mới phát
  hiện thì môn học đã bị xoá mất rồi.
- **Nếu giữ lại file `.md`**, hộp thoại cảnh báo rõ: lần "Nạp vào CSDL" kế tiếp
  sẽ dựng lại đúng môn vừa xoá. Đây là cái bẫy dễ mắc nhất của kiến trúc hai
  nguồn dữ liệu.

## 7. Những chỗ chống mất dữ liệu

| Rủi ro | Cách chặn |
| --- | --- |
| Tạo chu trình trong đồ thị tiên quyết | `_wouldCreateCycle()` duyệt ngược tổ tiên trước khi thêm cạnh |
| Môn tự trỏ chính nó | `CHECK (subject_id <> prerequisite_id)` ngay trong schema |
| Cạnh trùng lặp | `UNIQUE (subject_id, prerequisite_id)` |
| Xoá môn làm gãy lộ trình | `SubjectDeleteGuard` phân tích trước + hộp thoại cảnh báo + phương án nối tắt |
| Export đè mất ghi chú tự viết | `mergeMarkdown()` chỉ đụng ba khối app sở hữu |
| Import ghi mù vào CSDL | Tách `planImport()` / `applyPlan()`, xem trước rồi mới xác nhận |
| Xoá môn nhưng file `.md` còn lại | Cảnh báo môn sẽ bị tạo lại ở lần import sau |
| Gợi ý thứ tự học sai khi có chu trình | Kahn trả `null` thay vì đưa ra thứ tự không hợp lệ |
| Đổi nhà cung cấp AI làm mất API key | Mỗi provider một ô lưu riêng, có migration cho dữ liệu bản cũ |

## 8. Trạng thái hiện tại

```
flutter analyze  →  No issues found!
flutter test     →  66/66 All tests passed!
```

| Bộ test | Phạm vi |
| --- | --- |
| `graph_rag_test.dart` | Nhận diện môn từ câu hỏi: theo mã, theo từ khoá, viết tắt, không dấu, tiếng Anh, chống khớp bừa |
| `obsidian_parser_test.dart` | Regex wiki link và hashtag, front matter, `mergeMarkdown`, chỉ mục backlink |
| `subject_delete_guard_test.dart` | Phân loại rủi ro, đề xuất nối tắt, chặn chu trình, phát hiện môn đơn độc |
| `subject_delete_dialog_test.dart` | Hộp thoại cảnh báo xoá: nội dung theo mức rủi ro, lựa chọn trả về |

**Chưa làm:**

- Trang Cài đặt còn thiếu: nút Browse chọn Vault, nút mở Vault bằng chính app
  Obsidian, nút ẩn/hiện API key, nút kiểm tra kết nối tới API, nút cập nhật dữ
  liệu từ FAP, và nút Export/Import đặt ngay trong Cài đặt (hiện đang nằm ở tab
  Vault).
- `buildBacklinkIndex()` và `buildTagIndex()` đã có ở tầng service nhưng chưa
  màn hình nào dùng để vẽ thẻ màu / dropdown.
- `subject_form_dialog` chưa lọc theo `relation_type`, nên cạnh `RELATED` bị
  hiển thị lẫn trong mục môn tiên quyết.
- `flutter_markdown` đã bị ngừng hỗ trợ, cần chuyển sang `flutter_markdown_plus`.
