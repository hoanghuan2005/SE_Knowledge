import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import '../../models/curriculum.dart';
import '../../services/curriculum_cache_manager.dart';
import '../../services/curriculum_parser_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import 'syllabus_detail_dialog.dart';

/// Màn hình Demo bóc tách và chuẩn hóa khung chương trình FLM (Desktop)
class CurriculumDemoView extends StatefulWidget {
  const CurriculumDemoView({super.key});

  @override
  State<CurriculumDemoView> createState() => _CurriculumDemoViewState();
}

class _CurriculumDemoViewState extends State<CurriculumDemoView> {
  final TextEditingController _htmlController = TextEditingController();
  final TextEditingController _urlController = TextEditingController(
    text: 'https://flm.fpt.edu.vn/Curriculum/CurriculumDetail',
  );
  final TextEditingController _cookieController = TextEditingController();

  int _inputModeIndex = 0; // 0: Upload File HTML (Extension), 1: Dán mã HTML
  String? _uploadedFileName;
  int? _uploadedFileSize;

  Curriculum? _curriculum;
  bool _isLoading = false;
  String _dataSourceNote = 'Sẵn sàng';
  Color _dataSourceColor = Colors.grey;
  bool _hasCache = false;

  @override
  void initState() {
    super.initState();
    _htmlController.addListener(_onHtmlChanged);
    _checkCacheAndLoadInitial();
  }

  void _onHtmlChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _htmlController.removeListener(_onHtmlChanged);
    _htmlController.dispose();
    _urlController.dispose();
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _checkCacheAndLoadInitial() async {
    final cached = await CurriculumCacheManager.hasCache();
    if (mounted) {
      setState(() => _hasCache = cached);
      // Tự động nạp Offline-First khi mở màn hình (không auto-save DB để tránh ghi đè ban đầu)
      await _loadCurriculum(rawHtml: null, autoSaveToDb: false);
    }
  }

  /// Chọn file .html do Chrome Extension tải về máy
  Future<void> _pickHtmlFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'HTML Files',
        extensions: ['html', 'htm'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      final content = await file.readAsString();
      final size = await file.length();

      setState(() {
        _uploadedFileName = file.name;
        _uploadedFileSize = size;
        _htmlController.text = content;
        _dataSourceNote = 'Đã nạp file: ${file.name}';
        _dataSourceColor = Colors.teal;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B5E20),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '📄 Đã nạp file "${file.name}" (${(size / 1024).toStringAsFixed(1)} KB).\nBấm "Bóc Tách DOM" để chuẩn hóa môn học.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Lỗi khi đọc file HTML: $e'),
          ),
        );
      }
    }
  }

  void _clearUploadedFile() {
    setState(() {
      _uploadedFileName = null;
      _uploadedFileSize = null;
      _htmlController.clear();
      _dataSourceNote = 'Sẵn sàng';
      _dataSourceColor = Colors.grey;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _htmlController.text = data.text!;
        _uploadedFileName = null;
        _uploadedFileSize = null;
        _dataSourceNote = 'Đã dán HTML từ Clipboard (${_htmlController.text.length} ký tự)';
        _dataSourceColor = Colors.orange;
      });
    }
  }

  Future<void> _fetchFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _dataSourceNote = 'Đang gửi HTTP GET tới FLM...';
      _dataSourceColor = Colors.orange;
    });

    final service = CurriculumParserService.instance;
    final html = await service.fetchHtmlFromFlm(
      url: url,
      sessionCookie: _cookieController.text.trim(),
    );

    if (!mounted) return;

    if (html != null && html.isNotEmpty) {
      _htmlController.text = html;
      _uploadedFileName = null;
      _uploadedFileSize = null;

      final isLoginPage = html.contains('FPT Education Learning Materials - Login') ||
          html.contains('/gui/Account/Login') ||
          (html.contains('pagetitle') && html.toLowerCase().contains('login'));

      if (isLoginPage) {
        setState(() {
          _dataSourceNote = '⚠️ Cần Session Cookie (Bị chuyển hướng Login)';
          _dataSourceColor = Colors.orange;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.deepOrange,
            behavior: SnackBarBehavior.floating,
            content: Text(
              '⚠️ FLM yêu cầu đăng nhập! Hãy dán Session Cookie hoặc dùng Extension tải file HTML về máy.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
      await _loadCurriculum(rawHtml: html, forceRefresh: true);
    } else {
      setState(() {
        _isLoading = false;
        _dataSourceNote = 'Không kết nối được FLM. Nạp Offline Fallback.';
        _dataSourceColor = Colors.red;
      });
      await _loadCurriculum(rawHtml: null);
    }
  }

  Future<void> _syncToDatabase() async {
    if (_curriculum == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final res = await AppState.instance.importCurriculumToDb(_curriculum!);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1B5E20),
        behavior: SnackBarBehavior.floating,
        content: Text(
          '🎉 Đã đồng bộ vào CSDL: ${res.insertedSubjects} môn mới, ${res.updatedSubjects} môn cập nhật, ${res.insertedEdges} liên kết!\n👉 Mở tab "Graph view" để xem bản đồ học tập.',
        ),
      ),
    );
  }

  Future<void> _loadCurriculum({
    String? rawHtml,
    bool forceRefresh = false,
    bool autoSaveToDb = true,
  }) async {
    setState(() {
      _isLoading = true;
      _dataSourceNote = 'Đang xử lý qua Isolate compute()...';
      _dataSourceColor = Colors.orange;
    });

    final isLiveScrape = rawHtml != null && rawHtml.trim().isNotEmpty;
    final result = await AppState.instance.loadCurriculum(
      rawHtml: rawHtml,
      forceRefresh: forceRefresh,
      autoSaveToDb: isLiveScrape && autoSaveToDb,
    );

    final cachedExists = await CurriculumCacheManager.hasCache();

    if (!mounted) return;

    setState(() {
      _curriculum = result;
      _isLoading = false;
      _hasCache = cachedExists;

      if (isLiveScrape) {
        _dataSourceNote = 'Live HTML: Đã tự động lưu vào CSDL';
        _dataSourceColor = Colors.green;
      } else if (cachedExists) {
        _dataSourceNote = 'Nạp từ Local File Cache';
        _dataSourceColor = Colors.blue;
      } else {
        _dataSourceNote = 'Fallback: Mock Data (Chế độ Demo)';
        _dataSourceColor = Colors.purple;
      }
    });

    if (isLiveScrape && autoSaveToDb && mounted) {
      final res = AppState.instance.lastImportResult;
      final extra = res != null
          ? ' (+${res.insertedSubjects} môn mới, ${res.updatedSubjects} môn cập nhật, ${res.insertedEdges} liên kết)'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1B5E20),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '🎉 Đã cào & tự động lưu vào CSDL SQLite!$extra\n👉 Chuyển sang tab "Graph view" để xem bản đồ học tập ngay.',
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _clearCache() async {
    await CurriculumCacheManager.clearCache();
    final cached = await CurriculumCacheManager.hasCache();
    if (mounted) {
      setState(() => _hasCache = cached);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xoá file cache cục bộ.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidianWorkspace,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: AppBar(
          backgroundColor: AppColors.obsidianSidebar,
          elevation: 0,
          toolbarHeight: 44,
          automaticallyImplyLeading: false,
          titleSpacing: 14,
          shape: Border(
            bottom: BorderSide(color: AppColors.obsidianBorder),
          ),
          title: Row(
            children: [
              const Icon(Icons.school_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'FLM Curriculum Scraper & Normalizer',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                constraints: const BoxConstraints(maxWidth: 360),
                decoration: BoxDecoration(
                  color: _dataSourceColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _dataSourceColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _dataSourceColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _dataSourceNote,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _dataSourceColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Row(
        children: [
          // PANEL TRÁI: Nhập liệu (URL/Cookie, File Upload & Dán Text) + Điều khiển
          SizedBox(
            width: 400,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.obsidianSidebar,
                border: Border(
                  right: BorderSide(color: AppColors.obsidianBorder),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        child: Center(
                          child: Icon(Icons.tune_rounded, color: AppColors.primary, size: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'CÔNG CỤ CÀO DỮ LIỆU FLM',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: AppColors.obsidianTextMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // HTTP Fetch Section: Link URL + Session Cookie + Nút Cào
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'FLM Curriculum URL',
                      labelStyle: TextStyle(color: AppColors.obsidianTextMuted, fontSize: 12),
                      prefixIcon: const Icon(Icons.link, size: 16),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: AppColors.obsidianWorkspace,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: AppColors.obsidianBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: AppColors.obsidianBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _cookieController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Session Cookie (tuỳ chọn)',
                      labelStyle: TextStyle(color: AppColors.obsidianTextMuted, fontSize: 12),
                      prefixIcon: const Icon(Icons.cookie_outlined, size: 16),
                      hintText: 'ASP.NET_SessionId=...',
                      hintStyle: TextStyle(color: AppColors.obsidianTextMuted, fontSize: 11),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: AppColors.obsidianWorkspace,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: AppColors.obsidianBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: AppColors.obsidianBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.cloud_download_outlined, size: 15),
                    label: const Text(
                      'Cào Live từ Web FLM',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _isLoading ? null : _fetchFromUrl,
                  ),

                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: AppColors.obsidianBorder,
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'HOẶC DÙNG EXTENSION / HTML',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: AppColors.obsidianTextMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: AppColors.obsidianBorder,
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Thanh chọn 2 chế độ: Upload File HTML vs Dán Mã HTML
                  SegmentedButton<int>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.2),
                      selectedForegroundColor: Colors.white,
                      foregroundColor: AppColors.obsidianTextMuted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    ),
                    segments: const [
                      ButtonSegment<int>(
                        value: 0,
                        icon: Icon(Icons.file_upload_outlined, size: 15),
                        label: Text('Upload file HTML', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        icon: Icon(Icons.code_outlined, size: 15),
                        label: Text('Dán mã HTML', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    selected: {_inputModeIndex},
                    onSelectionChanged: (set) => setState(() => _inputModeIndex = set.first),
                  ),
                  const SizedBox(height: 8),

                  // Khung nội dung theo chế độ đã chọn (Upload File vs Paste Text)
                  Expanded(
                    child: _inputModeIndex == 0
                        ? _buildFileUploadView()
                        : _buildPasteTextView(),
                  ),

                  const SizedBox(height: 10),

                  // NÚT CHÍNH: Bóc Tách DOM Isolate
                  ListenableBuilder(
                    listenable: _htmlController,
                    builder: (context, _) {
                      final hasHtml = _htmlController.text.trim().isNotEmpty;
                      return ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.teal.withValues(alpha: 0.25),
                          disabledForegroundColor: Colors.white38,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          elevation: hasHtml ? 2 : 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: const Icon(Icons.bolt, size: 18),
                        label: Text(
                          _isLoading ? 'Đang bóc tách DOM...' : 'Bóc Tách DOM (Isolate compute)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: _isLoading || !hasHtml
                            ? null
                            : () => _loadCurriculum(
                                  rawHtml: _htmlController.text,
                                  forceRefresh: true,
                                ),
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  // THANH ACTION TOOLBAR: Sắp xếp các nút phụ thành icon có tooltip
                  Row(
                    children: [
                      // Nút Lưu vào CSDL nổi bật khi đã có kết quả
                      if (_curriculum != null && _curriculum!.semesters.isNotEmpty) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1B5E20),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            icon: const Icon(Icons.sync_alt, size: 15),
                            label: const Text(
                              'Lưu CSDL',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _isLoading ? null : _syncToDatabase,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Tooltip Icon: Mở thư mục Cache JSON
                      IconButton.outlined(
                        tooltip: 'Mở thư mục Cache JSON (Explorer)',
                        style: IconButton.styleFrom(
                          side: BorderSide(color: AppColors.obsidianBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          padding: const EdgeInsets.all(8),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.folder_open_outlined, size: 17),
                        onPressed: () => CurriculumCacheManager.openCacheFolder(),
                      ),
                      const SizedBox(width: 6),

                      // Tooltip Icon: Nạp dữ liệu mẫu (Offline Fallback)
                      IconButton.outlined(
                        tooltip: 'Thử Offline Fallback (Dữ liệu mẫu SE)',
                        style: IconButton.styleFrom(
                          side: BorderSide(color: AppColors.obsidianBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          padding: const EdgeInsets.all(8),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.science_outlined, size: 17),
                        onPressed: _isLoading ? null : () => _loadCurriculum(rawHtml: null),
                      ),
                      const SizedBox(width: 6),

                      // Tooltip Icon: Xoá Cache Cục Bộ
                      IconButton.outlined(
                        tooltip: 'Xoá Cache Cục Bộ',
                        style: IconButton.styleFrom(
                          side: BorderSide(
                            color: _hasCache ? Colors.redAccent.withValues(alpha: 0.4) : AppColors.obsidianBorder,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          padding: const EdgeInsets.all(8),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: Icon(
                          Icons.delete_outline,
                          size: 17,
                          color: _hasCache ? Colors.redAccent : Colors.grey,
                        ),
                        onPressed: _hasCache ? _clearCache : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),


          // PANEL PHẢI: Trực quan hóa Khung Chương Trình
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Đang bóc tách HTML trong Isolate nền...',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _curriculum == null || _curriculum!.semesters.isEmpty
                    ? Center(
                        child: Text(
                          'Chưa có dữ liệu. Vui lòng cào hoặc dán HTML.',
                          style: TextStyle(color: AppColors.obsidianTextMuted),
                        ),
                      )
                    : _buildCurriculumContent(_curriculum!),
          ),
        ],
      ),
    );
  }

  Widget _buildFileUploadView() {
    if (_uploadedFileName != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.obsidianWorkspace,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.html_outlined, color: Colors.tealAccent, size: 36),
            ),
            const SizedBox(height: 12),
            Text(
              _uploadedFileName!,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              '${((_uploadedFileSize ?? 0) / 1024).toStringAsFixed(1)} KB • ${_htmlController.text.length} ký tự',
              style: TextStyle(fontSize: 11, color: AppColors.obsidianTextMuted),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text('Đổi file khác', style: TextStyle(fontSize: 12)),
                  onPressed: _pickHtmlFile,
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('Gỡ', style: TextStyle(fontSize: 12)),
                  onPressed: _clearUploadedFile,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _pickHtmlFile,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.obsidianWorkspace,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.obsidianBorder, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_upload_outlined, color: AppColors.primaryLight, size: 36),
            ),
            const SizedBox(height: 14),
            const Text(
              'Chọn file HTML từ máy tính',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              'File .html do Extension của bạn tự động download về từ trang FLM',
              style: TextStyle(fontSize: 11, color: AppColors.obsidianTextMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: const Text('Chọn file HTML (.html)', style: TextStyle(fontSize: 12)),
              onPressed: _pickHtmlFile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteTextView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Mã nguồn HTML:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  icon: const Icon(Icons.content_paste_go, size: 14),
                  label: const Text('Dán Clipboard', style: TextStyle(fontSize: 11)),
                  onPressed: _pasteFromClipboard,
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _htmlController.clear();
                    _uploadedFileName = null;
                    _uploadedFileSize = null;
                  }),
                  child: const Text('Xoá', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: TextField(
            controller: _htmlController,
            maxLines: null,
            expands: true,
            onChanged: (val) {
              if (mounted) setState(() {});
            },
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
            ),
            decoration: InputDecoration(
              hintText: 'Dán chuỗi mã HTML (Ctrl+V) chứa bảng <table> môn học vào đây...',
              hintStyle: TextStyle(color: AppColors.obsidianTextMuted),
              filled: true,
              fillColor: AppColors.obsidianWorkspace,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.obsidianBorder),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurriculumContent(Curriculum curriculum) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Header Chuyên Ngành
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2C1B4D), Color(0xFF1E1E24)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.school, color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            curriculum.code,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            curriculum.major,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tổng cộng: ${curriculum.semesters.length} học kỳ  •  ${curriculum.totalCourses} môn học  •  ${curriculum.totalCredits > 0 ? curriculum.totalCredits : curriculum.calculatedTotalCredits} tín chỉ'
                      '${curriculum.decisionNo.isNotEmpty ? '  •  QĐ: ${curriculum.decisionNo}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.obsidianTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Danh sách các học kỳ
        ...curriculum.semesters.map((sem) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            color: AppColors.obsidianSidebar,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: AppColors.obsidianBorder),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Kỳ ${sem.termNumber}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              title: Text(
                'Học kỳ ${sem.termNumber}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                '${sem.courses.length} môn học  •  ${sem.totalCredits} tín chỉ',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.obsidianTextMuted,
                ),
              ),
              children: sem.courses.map((course) {
                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.obsidianBorder),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    leading: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.obsidianWorkspace,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.obsidianBorder),
                      ),
                      child: Text(
                        '${course.credits}TC',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    title: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: course.code,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.primaryLight,
                            ),
                          ),
                          if (course.name.isNotEmpty) ...[
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: course.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: course.prerequisites.isNotEmpty
                          ? Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  'Môn tiên quyết:',
                                  style: TextStyle(fontSize: 12),
                                ),
                                ...course.prerequisites.map(
                                  (p) => Chip(
                                    label: Text(
                                      p,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor:
                                        Colors.deepOrange.withValues(alpha: 0.2),
                                    side: BorderSide(
                                      color: Colors.deepOrange.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              'Không có môn tiên quyết',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.obsidianTextMuted,
                              ),
                            ),
                    ),
                    trailing: Tooltip(
                      message: 'Xem đề cương chi tiết môn học',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          side: BorderSide(color: AppColors.obsidianBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(Icons.auto_stories, size: 14, color: AppColors.primaryLight),
                        label: const Text('Syllabus', style: TextStyle(fontSize: 11)),
                        onPressed: () => SyllabusDetailDialog.show(context, subjectCode: course.code),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }
}
