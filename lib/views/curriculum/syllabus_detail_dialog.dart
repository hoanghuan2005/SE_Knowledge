import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/db_service.dart';
import '../../services/fap_markdown_parser.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';

/// Hộp thoại hiển thị chi tiết Đề cương môn học (Syllabus Details)
/// Được trích xuất từ FLM/FAP đã lưu trong CSDL SQLite.
class SyllabusDetailDialog extends StatefulWidget {
  final String? initialSubjectCode;
  final int? initialSubjectId;

  const SyllabusDetailDialog({
    super.key,
    this.initialSubjectCode,
    this.initialSubjectId,
  });

  static Future<void> show(
    BuildContext context, {
    String? subjectCode,
    int? subjectId,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SyllabusDetailDialog(
        initialSubjectCode: subjectCode,
        initialSubjectId: subjectId,
      ),
    );
  }

  @override
  State<SyllabusDetailDialog> createState() => _SyllabusDetailDialogState();
}

class _SyllabusDetailDialogState extends State<SyllabusDetailDialog> {
  bool _loading = true;
  String? _selectedCode;
  List<Map<String, dynamic>> _availableList = [];
  FapSyllabusImport? _syllabus;
  String _sessionSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.initialSubjectCode?.trim().toUpperCase();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final available = await DbService.instance.getAvailableSyllabi();
      _availableList = available;

      if (_selectedCode == null || _selectedCode!.isEmpty) {
        if (widget.initialSubjectId != null) {
          final found = available.firstWhere(
            (s) => s['subject_id'] == widget.initialSubjectId,
            orElse: () => <String, dynamic>{},
          );
          if (found.isNotEmpty) {
            _selectedCode = found['code'] as String?;
          }
        }
      }

      // Nếu vẫn chưa có mã môn được chọn, chọn môn đầu tiên trong danh sách
      if ((_selectedCode == null || _selectedCode!.isEmpty) && available.isNotEmpty) {
        _selectedCode = available.first['code'] as String?;
      }

      if (_selectedCode != null && _selectedCode!.isNotEmpty) {
        _syllabus = await DbService.instance.getSyllabusDetail(subjectCode: _selectedCode);
      }
    } catch (e) {
      if (mounted) Ui.error(context, 'Lỗi nạp Syllabus: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchSubject(String code) async {
    setState(() {
      _selectedCode = code;
      _loading = true;
      _sessionSearchQuery = '';
    });
    try {
      final syl = await DbService.instance.getSyllabusDetail(subjectCode: code);
      if (mounted) {
        setState(() {
          _syllabus = syl;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        Ui.error(context, 'Lỗi nạp Syllabus: $e');
      }
    }
  }

  Future<void> _openSourceUrl(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) Ui.info(context, 'Đã sao chép liên kết FLM vào bộ nhớ đệm.');
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) Ui.info(context, 'Đã sao chép liên kết FLM vào bộ nhớ đệm.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.85).clamp(820.0, 1180.0);
    final dialogHeight = (screenSize.height * 0.88).clamp(580.0, 860.0);

    return Dialog(
      backgroundColor: AppColors.obsidianSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.obsidianBorder),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _syllabus == null
                      ? _buildEmptyState()
                      : _buildSyllabusContent(_syllabus!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.obsidianWorkspace,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_stories, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          const Text(
            'Đề cương môn học (Syllabus FLM)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 18),
          // Dropdown chuyển nhanh môn học
          if (_availableList.isNotEmpty)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.obsidianSidebar,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.obsidianBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _availableList.any((s) => s['code'] == _selectedCode)
                          ? _selectedCode
                          : null,
                      isExpanded: true,
                      dropdownColor: AppColors.obsidianSidebar,
                      hint: const Text(
                        'Chọn môn học đã có Syllabus...',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      items: _availableList.map((s) {
                        final code = s['code'] as String;
                        final name = s['name'] as String? ?? '';
                        return DropdownMenuItem<String>(
                          value: code,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  code,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryLight,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedCode) {
                          _switchSubject(val);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          if (_syllabus?.sourceUrl.isNotEmpty ?? false) ...[
            const SizedBox(width: 10),
            Tooltip(
              message: 'Mở trang gốc trên FLM / Sao chép liên kết',
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  side: BorderSide(color: AppColors.obsidianBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.open_in_browser, size: 16),
                label: const Text('FLM Link', style: TextStyle(fontSize: 11)),
                onPressed: () => _openSourceUrl(_syllabus!.sourceUrl),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Đóng',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 56, color: AppColors.obsidianTextMuted),
            const SizedBox(height: 16),
            Text(
              _selectedCode != null
                  ? 'Môn "$_selectedCode" chưa có dữ liệu Syllabus'
                  : 'Chưa có dữ liệu Syllabus nào',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Bạn có thể vào trang Syllabus Details trên FLM và dùng Extension để lưu về, '
              'hoặc sao chép file Markdown vào thư mục FAP để tự động nạp.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyllabusContent(FapSyllabusImport data) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          // Banner tóm tắt môn học
          _buildSummaryBanner(data),
          // Tab bar điều hướng
          Container(
            color: AppColors.obsidianWorkspace,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: AppColors.obsidianTextMuted,
              labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 12.5),
              tabs: [
                const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Tổng quan'),
                Tab(
                  icon: const Icon(Icons.library_books_outlined, size: 16),
                  text: 'Giáo trình (${data.materials.length})',
                ),
                Tab(
                  icon: const Icon(Icons.track_changes_outlined, size: 16),
                  text: 'Chuẩn đầu ra CLO (${data.clos.length})',
                ),
                Tab(
                  icon: const Icon(Icons.calendar_month_outlined, size: 16),
                  text: 'Kế hoạch học tập (${data.sessions.length} buổi)',
                ),
                Tab(
                  icon: const Icon(Icons.assessment_outlined, size: 16),
                  text: 'Đánh giá (${data.assessments.length} đầu điểm)',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Nội dung từng tab
          Expanded(
            child: TabBarView(
              children: [
                _buildOverviewTab(data),
                _buildMaterialsTab(data),
                _buildClosTab(data),
                _buildSessionsTab(data),
                _buildAssessmentsTab(data),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner(FapSyllabusImport data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.obsidianSidebar,
        border: Border(bottom: BorderSide(color: AppColors.obsidianBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  data.subjectCode,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  data.displayName,
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (data.degreeLevel.isNotEmpty)
                _ChipBadge(
                  icon: Icons.school_outlined,
                  label: data.degreeLevel,
                  color: Colors.blueAccent,
                ),
              if (data.timeAllocation.isNotEmpty)
                _ChipBadge(
                  icon: Icons.timer_outlined,
                  label: data.timeAllocation.split('=').first.trim(),
                  color: Colors.purpleAccent,
                ),
              if (data.scoringScale != null)
                _ChipBadge(
                  icon: Icons.military_tech_outlined,
                  label: 'Thang ${data.scoringScale}',
                  color: Colors.tealAccent,
                ),
              if (data.minAvgMarkToPass != null)
                _ChipBadge(
                  icon: Icons.check_circle_outline,
                  label: 'Qua môn: ≥ ${data.minAvgMarkToPass}',
                  color: Colors.greenAccent,
                ),
              if (data.decisionNo.isNotEmpty)
                _ChipBadge(
                  icon: Icons.description_outlined,
                  label: data.decisionNo,
                  color: Colors.amberAccent,
                ),
              _ChipBadge(
                icon: data.isApproved ? Icons.verified_outlined : Icons.pending_outlined,
                label: data.isApproved ? 'Đã duyệt' : 'Chưa duyệt',
                color: data.isApproved ? Colors.green : Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- TAB 1: TỔNG QUAN ---
  Widget _buildOverviewTab(FapSyllabusImport data) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (data.description.isNotEmpty) ...[
          _SectionCard(
            title: 'Mô tả môn học (Course Description)',
            icon: Icons.subject,
            content: Text(
              data.description,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (data.learningTeachingMethod.isNotEmpty) ...[
          _SectionCard(
            title: 'Phương pháp học tập & giảng dạy (Learning-Teaching Method)',
            icon: Icons.psychology_outlined,
            content: Text(
              data.learningTeachingMethod,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (data.timeAllocation.isNotEmpty) ...[
          _SectionCard(
            title: 'Phân bổ thời lượng học tập (Time Allocation)',
            icon: Icons.schedule,
            content: Text(
              data.timeAllocation,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (data.rawPrerequisiteText.isNotEmpty) ...[
          _SectionCard(
            title: 'Điều kiện tiên quyết (Pre-requisite)',
            icon: Icons.link,
            content: Text(
              data.rawPrerequisiteText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (data.studentTasks.isNotEmpty) ...[
          _SectionCard(
            title: 'Nhiệm vụ của sinh viên (Student Tasks)',
            icon: Icons.task_alt,
            content: Text(
              data.studentTasks,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (data.tools.isNotEmpty) ...[
          _SectionCard(
            title: 'Công cụ & Phần mềm yêu cầu (Tools / Software)',
            icon: Icons.construction,
            content: Text(
              data.tools,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  // --- TAB 2: GIÁO TRÌNH & TÀI LIỆU ---
  Widget _buildMaterialsTab(FapSyllabusImport data) {
    if (data.materials.isEmpty) {
      return _emptyTabMessage('Không có thông tin giáo trình / tài liệu trong Syllabus này.');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: data.materials.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final m = data.materials[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.obsidianWorkspace,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: m.isMain ? AppColors.primary.withValues(alpha: 0.5) : AppColors.obsidianBorder,
              width: m.isMain ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: m.isMain ? AppColors.primary : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      m.isMain ? 'GIÁO TRÌNH CHÍNH' : 'TÀI LIỆU #${m.seqNo}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (m.isOnline)
                    _MiniBadge(label: 'Online', color: Colors.cyanAccent),
                  if (m.isHardCopy)
                    _MiniBadge(label: 'Sách giấy', color: Colors.amberAccent),
                  const Spacer(),
                  if (m.isbn.isNotEmpty)
                    Text(
                      'ISBN: ${m.isbn}',
                      style: TextStyle(fontSize: 11, color: AppColors.obsidianTextMuted),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                m.description,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, height: 1.3),
              ),
              if (m.author.isNotEmpty || m.publisher.isNotEmpty || m.publishedDate.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (m.author.isNotEmpty) 'Tác giả: ${m.author}',
                    if (m.publisher.isNotEmpty) 'NXB: ${m.publisher}',
                    if (m.publishedDate.isNotEmpty) 'Năm: ${m.publishedDate}',
                    if (m.edition.isNotEmpty) 'Bản in: ${m.edition}',
                  ].join('  ·  '),
                  style: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
                ),
              ],
              if (m.note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Ghi chú: ${m.note}',
                  style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Colors.orangeAccent),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- TAB 3: CHUẨN ĐẦU RA (CLO) ---
  Widget _buildClosTab(FapSyllabusImport data) {
    if (data.clos.isEmpty) {
      return _emptyTabMessage('Không có thông tin chuẩn đầu ra (CLO) trong Syllabus này.');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: data.clos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final clo = data.clos[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.obsidianWorkspace,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.obsidianBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 68,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: Text(
                  clo.code,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryLight,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  clo.detail,
                  style: const TextStyle(fontSize: 13, height: 1.45),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- TAB 4: KẾ HOẠCH HỌC TẬP (60 BUỔI) ---
  Widget _buildSessionsTab(FapSyllabusImport data) {
    if (data.sessions.isEmpty) {
      return _emptyTabMessage('Chưa có thông tin kế hoạch buổi học.');
    }

    final query = _sessionSearchQuery.trim().toLowerCase();
    final filteredSessions = query.isEmpty
        ? data.sessions
        : data.sessions.where((s) {
            return s.sessionNo.toString() == query ||
                s.topic.toLowerCase().contains(query) ||
                s.teachingType.toLowerCase().contains(query) ||
                s.studentTasks.toLowerCase().contains(query) ||
                s.cloCodes.any((c) => c.toLowerCase().contains(query));
          }).toList();

    return Column(
      children: [
        // Ô tìm kiếm buổi học
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: TextField(
            onChanged: (val) => setState(() => _sessionSearchQuery = val),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Tìm kiếm theo số buổi, chủ đề, hình thức học, CLO...',
              hintStyle: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() => _sessionSearchQuery = ''),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              filled: true,
              fillColor: AppColors.obsidianWorkspace,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.obsidianBorder),
              ),
            ),
          ),
        ),
        // Header bảng buổi học
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          color: AppColors.obsidianWorkspace,
          child: const Row(
            children: [
              SizedBox(width: 64, child: Text('BUỔI', style: _colHeaderStyle)),
              Expanded(flex: 4, child: Text('CHỦ ĐỀ (TOPIC)', style: _colHeaderStyle)),
              SizedBox(width: 90, child: Text('HÌNH THỨC', style: _colHeaderStyle)),
              Expanded(flex: 3, child: Text('NHIỆM VỤ / TÀI LIỆU', style: _colHeaderStyle)),
              SizedBox(width: 110, child: Text('CLO ĐẠT ĐƯỢC', style: _colHeaderStyle)),
            ],
          ),
        ),
        const Divider(height: 1),
        // Danh sách buổi học
        Expanded(
          child: filteredSessions.isEmpty
              ? Center(
                  child: Text(
                    'Không tìm thấy buổi học nào khớp với "$query"',
                    style: TextStyle(color: AppColors.obsidianTextMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: filteredSessions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = filteredSessions[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      color: i.isEven
                          ? AppColors.obsidianSidebar
                          : AppColors.obsidianWorkspace.withValues(alpha: 0.5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Buổi số
                          SizedBox(
                            width: 64,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.obsidianBorder,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#${s.sessionNo}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          // Chủ đề
                          Expanded(
                            flex: 4,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(
                                s.topic,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          // Hình thức
                          SizedBox(
                            width: 90,
                            child: Text(
                              s.teachingType.isEmpty ? 'Offline' : s.teachingType,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: s.teachingType.toLowerCase().contains('online')
                                    ? Colors.cyanAccent
                                    : AppColors.obsidianTextMuted,
                              ),
                            ),
                          ),
                          // Nhiệm vụ sinh viên
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(
                                s.studentTasks.isNotEmpty
                                    ? s.studentTasks
                                    : (s.studentMaterials.isNotEmpty ? s.studentMaterials : '-'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: AppColors.obsidianTextMuted),
                              ),
                            ),
                          ),
                          // CLO
                          SizedBox(
                            width: 110,
                            child: s.cloCodes.isNotEmpty
                                ? Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: s.cloCodes.map((c) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(color: Colors.teal.withValues(alpha: 0.5)),
                                        ),
                                        child: Text(
                                          c,
                                          style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
                                        ),
                                      );
                                    }).toList(),
                                  )
                                : Text('-', style: TextStyle(fontSize: 11, color: AppColors.obsidianTextMuted)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- TAB 5: ĐÁNH GIÁ (ASSESSMENTS) ---
  Widget _buildAssessmentsTab(FapSyllabusImport data) {
    if (data.assessments.isEmpty) {
      return _emptyTabMessage('Chưa có thông tin đầu điểm đánh giá.');
    }

    final totalWeight = data.assessments.fold<double>(0.0, (sum, a) => sum + a.weightPercent);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Thanh tổng trọng số
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.obsidianWorkspace,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.obsidianBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.pie_chart_outline, size: 18, color: AppColors.primaryLight),
              const SizedBox(width: 10),
              const Text(
                'Tổng trọng số các đầu điểm:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${totalWeight.toStringAsFixed(totalWeight.truncateToDouble() == totalWeight ? 0 : 1)}%',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: (totalWeight >= 99.0 && totalWeight <= 101.0)
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Danh sách các đầu điểm
        ...data.assessments.map((a) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.obsidianWorkspace,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.obsidianBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#${a.seqNo}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.category,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '${a.weightPercent}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (a.type.isNotEmpty)
                      _AssessmentAttr(label: 'Loại bài', value: a.type),
                    if (a.completionCriteria.isNotEmpty)
                      _AssessmentAttr(label: 'Tiêu chí', value: a.completionCriteria),
                    if (a.duration.isNotEmpty)
                      _AssessmentAttr(label: 'Thời gian', value: a.duration),
                    if (a.questionType.isNotEmpty)
                      _AssessmentAttr(label: 'Hình thức', value: a.questionType),
                  ],
                ),
                if (a.cloCodes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Đo lường CLO: ', style: TextStyle(fontSize: 11.5, color: AppColors.obsidianTextMuted)),
                      Wrap(
                        spacing: 4,
                        children: a.cloCodes.map((c) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(c, style: const TextStyle(fontSize: 10.5, color: Colors.tealAccent)),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ],
                if (a.note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Ghi chú: ${a.note}',
                    style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.orangeAccent),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _emptyTabMessage(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          msg,
          style: TextStyle(fontSize: 13, color: AppColors.obsidianTextMuted),
        ),
      ),
    );
  }
}

const _colHeaderStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.bold,
  color: Colors.grey,
  letterSpacing: 0.5,
);

class _ChipBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ChipBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget content;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.obsidianWorkspace,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.obsidianBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primaryLight),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }
}

class _AssessmentAttr extends StatelessWidget {
  final String label;
  final String value;

  const _AssessmentAttr({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: TextStyle(fontSize: 11.5, color: AppColors.obsidianTextMuted)),
        Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
