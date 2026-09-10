# SE Knowledge

Ứng dụng desktop quản lý **bản đồ tri thức môn học** theo phong cách Obsidian.
Một project Flutter duy nhất, một file SQLite duy nhất, chạy offline 100%.

## Kiến trúc

**Standalone Desktop App + Embedded Database.** Không có Spring Boot, không có
MySQL, không có Docker.

| Thành phần | Công nghệ |
| --- | --- |
| Giao diện & ngôn ngữ | Flutter Desktop, Dart thuần |
| Cơ sở dữ liệu | SQLite nhúng qua `sqflite_common_ffi` |
| Đọc/ghi ghi chú `.md` | `dart:io` thuần, tự parse cú pháp `[[...]]` |
| Trực quan đồ thị | `graphview` |
| Trợ lý AI | `http` gọi thẳng REST API của Gemini / OpenAI |
| Cấu hình cục bộ | `shared_preferences` |
| Chọn thư mục Vault | `file_selector` |

### Vì sao không dùng web app hay server

Obsidian là công cụ **Local-First**: file trên máy người dùng là nguồn sự thật,
và quyền riêng tư dữ liệu tệp tin là một yêu cầu thiết kế, không phải tuỳ chọn.
Đặt một application server và một database server vào giữa một tiện ích chạy cục
bộ là **phản kiến trúc**: thêm điểm hỏng hóc, thêm độ trễ, thêm bề mặt rò rỉ dữ
liệu, mà không đổi lại giá trị nào cho người dùng đơn lẻ.

Toàn bộ hệ thống vì thế gói trong một tiến trình Flutter. Mạng chỉ được dùng khi
người dùng chủ động chat với trợ lý AI.

### Vẫn là cơ sở dữ liệu quan hệ đầy đủ

SQLite dùng SQL chuẩn và giữ nguyên mọi ràng buộc quan hệ. Xem
[db_service.dart](lib/services/db_service.dart).

```sql
CREATE TABLE subjects (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT    NOT NULL UNIQUE,
  name        TEXT    NOT NULL,
  semester    INTEGER NOT NULL DEFAULT 1,
  credits     INTEGER NOT NULL DEFAULT 3,
  description TEXT    NOT NULL DEFAULT '',
  note_path   TEXT,
  created_at  TEXT    NOT NULL,
  updated_at  TEXT    NOT NULL
);

CREATE TABLE prerequisites (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  subject_id      INTEGER NOT NULL,
  prerequisite_id INTEGER NOT NULL,
  relation_type   TEXT    NOT NULL DEFAULT 'PREREQUISITE',
  UNIQUE (subject_id, prerequisite_id),
  CHECK (subject_id <> prerequisite_id),
  FOREIGN KEY (subject_id)      REFERENCES subjects (id) ON DELETE CASCADE,
  FOREIGN KEY (prerequisite_id) REFERENCES subjects (id) ON DELETE CASCADE
);
```

`subjects` là tập **node**, `prerequisites` là tập **edge** của đồ thị. Bảng edge
tự tham chiếu bảng node bằng hai khoá ngoại, nên xoá một môn sẽ tự dọn sạch mọi
liên kết nhờ `ON DELETE CASCADE`. Ngoài ràng buộc CSDL, tầng service còn chặn
chu trình trước khi ghi, để đồ thị luôn là một DAG hợp lệ.

## Cấu trúc thư mục `lib/`

```
lib/
├── main.dart                      Khởi tạo SQLite FFI rồi chạy app
├── models/
│   ├── subject.dart               Node: một môn học
│   ├── prerequisite.dart          Edge: quan hệ tiên quyết
│   ├── graph_data.dart            Gói node + edge cho tầng hiển thị
│   └── chat_message.dart          Một lượt hội thoại AI
├── services/
│   ├── db_service.dart            SQLite: schema, CRUD, JOIN, sắp xếp topo
│   ├── obsidian_service.dart      dart:io: quét Vault, parse [[...]], ghi .md
│   ├── ai_service.dart            http: gọi Gemini / OpenAI
│   └── settings_service.dart      Cấu hình cục bộ, API key
├── state/
│   └── app_state.dart             ChangeNotifier dùng chung mọi màn hình
├── utils/                         Màu, theme, hằng số, widget tiện ích
└── views/
    ├── app_shell.dart             Khung desktop, thanh điều hướng dọc
    ├── graph/graph_page.dart      Đồ thị graphview, hai kiểu bố cục
    ├── subjects/                  Bảng môn học, form thêm/sửa, thêm liên kết
    ├── vault/vault_page.dart      Đồng bộ hai chiều với Obsidian Vault
    ├── chat/ai_chat_page.dart     Khung chat trợ lý học tập
    ├── settings/settings_page.dart Cấu hình và thông tin kiến trúc
    └── widgets/                   Bảng chi tiết môn dùng chung
```

## Chạy ứng dụng

```bash
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
```

Build bản phát hành:

```bash
flutter build windows --release
```

Chạy kiểm thử phần bóc tách Markdown:

```bash
flutter test
```

## Cách dùng

1. **Đồ thị.** Mở app là có sẵn dữ liệu mẫu. Cuộn để zoom, kéo để di chuyển,
   bấm một node để xem chi tiết bên phải. Đổi giữa bố cục *Phân tầng* (đọc lộ
   trình học từ trên xuống) và *Lực đẩy* (cụm nơ-ron kiểu Obsidian Graph View).
2. **Môn học.** Thêm, sửa, xoá môn và liên kết tiên quyết. Nút *Gợi ý lộ trình*
   chạy sắp xếp topo bằng thuật toán Kahn trên đồ thị.
3. **Vault.** Chọn thư mục Obsidian Vault. *Nạp vào CSDL* quét mọi file `.md`,
   đọc `[[Tên môn]]` dưới mục **Môn tiên quyết** và dựng lại đồ thị. *Ghi ra
   Vault* làm ngược lại, sinh một file `<MÃ MÔN>.md` cho mỗi môn kèm front
   matter và các wiki link.
4. **Trợ lý AI.** Nhập API key ở tab Cài đặt trước. Mỗi câu hỏi được gửi kèm
   ngữ cảnh lấy từ SQLite, nên AI trả lời dựa trên đúng đồ thị của bạn. Tắt
   công tắc *Gửi kèm ngữ cảnh* nếu không muốn gửi dữ liệu môn học đi.

## Quy ước file Markdown

App đặt tên file theo mã môn để `[[PRF192]]` trong Obsidian luôn resolve được.

```markdown
---
code: CSD201
name: "Data Structures and Algorithms"
semester: 2
credits: 3
tags: [subject, semester-2]
---

# CSD201 — Data Structures and Algorithms

Cấu trúc dữ liệu và thuật toán.

## Môn tiên quyết
- [[PRF192]] — Programming Fundamentals
- [[MAD101]] — Discrete Mathematics

## Mở ra các môn
- [[PRJ301]] — Java Web Application Development

## Ghi chú
Phần này do bạn tự viết, app không ghi đè khi export lại.
```

## Dữ liệu nằm ở đâu

File SQLite nằm trong thư mục dữ liệu ứng dụng của người dùng
(`getApplicationSupportDirectory()`); đường dẫn đầy đủ hiện trong tab **Cài
đặt**. Ghi chú `.md` nằm trong Vault bạn tự chọn. API key lưu cục bộ qua
`shared_preferences`, không có trong source code và không bị commit lên Git.
