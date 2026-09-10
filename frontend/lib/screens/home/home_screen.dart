import 'package:flutter/material.dart';
import '../../components/custom_button.dart';
import '../../components/custom_text_field.dart';
import '../../models/user_model.dart';
import '../../routes/app_routes.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_constants.dart';

/// Màn hình Home mẫu giới thiệu cấu trúc dự án cho các thành viên trong team.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;

  // Dữ liệu mẫu (Mock data)
  final UserModel _mockUser = UserModel(
    id: '1',
    email: 'student@fpt.edu.vn',
    fullName: 'FPT SE Student',
    role: 'Student',
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleButtonPress() {
    setState(() => _isLoading = true);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CustomButton đã hoạt động thành công!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.of(context).pushNamed(
                AppRoutes.home,
                arguments: {'title': 'Sample Arguments'},
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card chào mừng
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.primaryLight,
                      child: Icon(Icons.person, color: AppColors.primaryDark, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Xin chào, ${_mockUser.fullName}!',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _mockUser.email,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Mục hướng dẫn cấu trúc cho team
            const Text(
              'Cấu trúc thư mục lib/ (Base Architecture)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildFolderGuide(
              folder: 'routes/',
              description: 'Định nghĩa tên routes và bộ điều hướng onGenerateRoute.',
              icon: Icons.alt_route,
            ),
            _buildFolderGuide(
              folder: 'screens/',
              description: 'Chứa các màn hình giao diện (UI screens/pages).',
              icon: Icons.smartphone,
            ),
            _buildFolderGuide(
              folder: 'components/',
              description: 'Chứa các reusable widgets (buttons, dialogs, textfields,...).',
              icon: Icons.widgets,
            ),
            _buildFolderGuide(
              folder: 'models/',
              description: 'Chứa các Data Models (fromJson, toJson, copyWith).',
              icon: Icons.data_object,
            ),
            _buildFolderGuide(
              folder: 'services/',
              description: 'Gọi API, kết nối backend, quản lý storage/cache.',
              icon: Icons.cloud_sync,
            ),
            _buildFolderGuide(
              folder: 'utils/',
              description: 'Hằng số constants, bảng màu AppColors, AppTheme.',
              icon: Icons.build_circle_outlined,
            ),

            const SizedBox(height: 24),
            const Text(
              'Demo Reusable Components',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Demo CustomTextField
            CustomTextField(
              controller: _searchController,
              hintText: 'Tìm kiếm tài liệu môn học...',
              labelText: 'Từ khóa tìm kiếm',
              prefixIcon: Icons.search,
            ),
            const SizedBox(height: 16),

            // Demo CustomButton
            CustomButton(
              text: 'Thử nghiệm CustomButton',
              icon: Icons.check_circle_outline,
              isLoading: _isLoading,
              onPressed: _handleButtonPress,
            ),
            const SizedBox(height: 12),

            // Demo Test 404 Route
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pushNamed('/unknown-test-route');
              },
              child: const Text('Test điều hướng 404 Route'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderGuide({
    required String folder,
    required String description,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            folder,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
