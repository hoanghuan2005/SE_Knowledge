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

## Cài đặt môi trường cho thành viên mới

Chỉ cần ba thứ. Không cần JDK, Maven, MySQL, Docker hay Android SDK.

| Cần cài | Vì sao |
| --- | --- |
| Flutter SDK 3.47.3 stable trở lên | Project yêu cầu Dart `^3.13.3` |
| Visual Studio Build Tools 2022, workload C++ | Biên dịch `windows/runner` thành `.exe` |
| Developer Mode của Windows | Flutter tạo symlink cho plugin native |

### Cách nhanh, một lệnh

Mở **Windows PowerShell** tại thư mục gốc project rồi chạy:

```powershell
powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1
```

Script [tools/setup_windows.ps1](tools/setup_windows.ps1) làm gần hết mọi việc:
tải và giải nén Flutter ra `C:\src\flutter`, thêm vào PATH của User, cài
Visual Studio Build Tools qua winget, chạy `flutter pub get`, rồi in
`flutter doctor`. Chạy lại nhiều lần được, bước nào xong rồi thì tự bỏ qua.

Hai việc script không tự làm được, nó sẽ nhắc ở cuối:

- **Bật Developer Mode.** Việc này cần quyền Administrator. Script tự mở cửa sổ
  Settings, bạn chỉ việc bấm công tắc ở dòng đầu tiên.
- **Mở lại IntelliJ và terminal.** Tiến trình đọc PATH đúng lúc nó khởi động,
  nên phải đóng hẳn rồi mở lại mới thấy lệnh `flutter`. Mở tab terminal mới bên
  trong IntelliJ cũ thì không ăn.

Visual Studio Build Tools **không phải IDE**, nó không có editor và không mở lên
được. Đó chỉ là compiler MSVC kèm Windows SDK và CMake mà Flutter gọi ngầm. Bạn
vẫn code hoàn toàn trong IntelliJ.

### Kiểm tra

```powershell
flutter doctor
```

Ba dòng **Flutter**, **Windows Version** và **Visual Studio** phải xanh. Dòng
**Android toolchain** báo đỏ là bình thường, project này build desktop nên không
dùng Android SDK.

### Nếu muốn làm thủ công

Chỉ làm khi không muốn chạy script. Lưu ý PowerShell 5.1 không hỗ trợ toán tử
`&&`, muốn nối nhiều lệnh thì dùng dấu `;`.

```powershell
Invoke-WebRequest -Uri "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.3-stable.zip" -OutFile "$env:TEMP\flutter.zip"
```

```powershell
Expand-Archive -Path "$env:TEMP\flutter.zip" -DestinationPath "C:\src"
```

```powershell
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';C:\src\flutter\bin', 'User')
```

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --override "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.CMake.Project --includeRecommended"
```

```powershell
start ms-settings:developers
```

Nếu thích sửa PATH bằng giao diện thì nhấn `Windows + R`, gõ `sysdm.cpl`, vào
tab **Advanced**, bấm **Environment Variables**, chọn dòng **Path** ở khung
**trên** là *User variables*, bấm **Edit**, bấm **New**, gõ
`C:\src\flutter\bin`, rồi bấm **OK** ba lần.

## Chạy ứng dụng

Sau khi `git clone` hoặc `git pull`, thư mục `.dart_tool/` và `build/` không nằm
trong Git nên phải nạp lại dependency trước.

```bash
flutter pub get
```

```bash
flutter run -d windows
```

Build bản phát hành:

```bash
flutter build windows --release
```

Chạy kiểm thử phần bóc tách Markdown, việc này không cần Visual Studio:

```bash
flutter test
```

Trong IntelliJ IDEA, cần bản có plugin **Flutter** và **Dart**. Vào Settings,
Languages & Frameworks, Flutter, rồi trỏ Flutter SDK path tới `C:\src\flutter`.
Chọn device `Windows (desktop)` trên thanh công cụ rồi bấm Run.

Không có bước nào phải import cơ sở dữ liệu. Lần chạy đầu tiên app tự tạo file
`se_knowledge.db` kèm dữ liệu mẫu. API key của trợ lý AI là tuỳ chọn, thiếu nó
thì bốn tab còn lại vẫn hoạt động bình thường.

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
