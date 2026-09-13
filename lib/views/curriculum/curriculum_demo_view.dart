import 'package:flutter/material.dart';
import '../../models/curriculum.dart';
import '../../services/curriculum_cache_manager.dart';
import '../../services/curriculum_parser_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';

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

  Curriculum? _curriculum;
  bool _isLoading = false;
  String _dataSourceNote = 'Sẵn sàng';
  Color _dataSourceColor = Colors.grey;
  bool _hasCache = false;

  @override
  void initState() {
    super.initState();
    _checkCacheAndLoadInitial();
  }

  @override
  void dispose() {
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
      final isLoginPage = html.contains('FPT Education Learning Materials - Login') ||
          html.contains('/gui/Account/Login') ||
          (html.contains('pagetitle') && html.toLowerCase().contains('login'));

      if (isLoginPage) {
        if (!mounted) return;
        setState(() {
          _dataSourceNote = '⚠️ Cần Session Cookie (Bị chuyển hướng Login)';
          _dataSourceColor = Colors.orange;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.deepOrange,
            behavior: SnackBarBehavior.floating,
            content: Text(
              '⚠️ FLM yêu cầu đăng nhập! Hãy dán Session Cookie hoặc bấm Ctrl+U ở tab FLM rồi copy toàn bộ HTML dán vào ô bên dưới.',
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
      // Fallback ngay lập tức khi mạng lỗi
      await _loadCurriculum(rawHtml: null);
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
      appBar: AppBar(
        backgroundColor: AppColors.obsidianSidebar,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.school_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            const Text(
              'FLM Curriculum Scraper & Normalizer (Desktop)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _dataSourceColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _dataSourceColor.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _dataSourceColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _dataSourceNote,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _dataSourceColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Row(
        children: [
          // PANEL TRÁI: Nhập liệu & Điều khiển Demo
          SizedBox(
            width: 380,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.obsidianSidebar,
                border: Border(
                  right: BorderSide(color: AppColors.obsidianBorder),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'CÔNG CỤ CÀO DỮ LIỆU FLM',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // HTTP Fetch Section
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'FLM Curriculum URL',
                      labelStyle: TextStyle(color: AppColors.obsidianTextMuted),
                      prefixIcon: const Icon(Icons.link, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cookieController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Session Cookie (tuỳ chọn)',
                      labelStyle: TextStyle(color: AppColors.obsidianTextMuted),
                      prefixIcon: const Icon(Icons.cookie_outlined, size: 18),
                      hintText: 'ASP.NET_SessionId=...',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('Cào Live từ Web FLM'),
                    onPressed: _isLoading ? null : _fetchFromUrl,
                  ),

                  const Divider(height: 24),

                  // Raw HTML Paste Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Mã nguồn HTML (Ctrl+U):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _htmlController.clear(),
                        child: const Text('Xoá', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: TextField(
                      controller: _htmlController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'Consolas',
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Dán chuỗi HTML chứa bảng <table> môn học vào đây...',
                        hintStyle:
                            TextStyle(color: AppColors.obsidianTextMuted),
                        filled: true,
                        fillColor: AppColors.obsidianWorkspace,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.obsidianBorder),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Nút Parse Isolate
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.bolt, size: 18),
                    label: const Text(
                      'Bóc Tách DOM (Isolate compute)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isLoading || _htmlController.text.trim().isEmpty
                        ? null
                        : () => _loadCurriculum(
                              rawHtml: _htmlController.text,
                              forceRefresh: true,
                            ),
                  ),

                  const SizedBox(height: 8),

                  // Test nút Offline Fallback
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.wifi_off, size: 16),
                          label: const Text('Thử Offline Fallback'),
                          onPressed: _isLoading
                              ? null
                              : () => _loadCurriculum(rawHtml: null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Xoá Cache Cục Bộ',
                        icon: Icon(
                          Icons.delete_sweep_outlined,
                          color: _hasCache ? Colors.redAccent : Colors.grey,
                        ),
                        onPressed: _hasCache ? _clearCache : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: const Text('Mở file Cache JSON (Explorer)'),
                    onPressed: () => CurriculumCacheManager.openCacheFolder(),
                  ),
                  if (_curriculum != null && _curriculum!.semesters.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.tealAccent,
                        side: BorderSide(
                          color: Colors.tealAccent.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.sync_alt, size: 16),
                      label: const Text('Đồng bộ dữ liệu này vào CSDL'),
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final res = await AppState.instance
                                  .importCurriculumToDb(_curriculum!);
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF1B5E20),
                                  behavior: SnackBarBehavior.floating,
                                  content: Text(
                                    '🎉 Đã đồng bộ vào CSDL: ${res.insertedSubjects} môn mới, ${res.updatedSubjects} môn cập nhật, ${res.insertedEdges} liên kết!',
                                  ),
                                ),
                              );
                            },
                    ),
                  ],
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
