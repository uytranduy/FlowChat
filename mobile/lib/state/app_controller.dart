import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/friend_service.dart';
import '../services/user_service.dart';
import 'call_controller.dart';
import 'group_call_controller.dart';

class AppController extends ChangeNotifier {
  AppController({ApiClient? apiClient}) : apiClient = apiClient ?? ApiClient() {
    authService = AuthService(this.apiClient);
    chatService = ChatService(this.apiClient);
    friendService = FriendService(this.apiClient);
    userService = UserService(this.apiClient);
    callController = CallController(this.apiClient.tokenStorage);
    groupCallController = GroupCallController(this.apiClient.tokenStorage);
  }

  static const _darkModeKey = 'flowchat_dark_mode';

  final ApiClient apiClient;
  late final AuthService authService;
  late final ChatService chatService;
  late final FriendService friendService;
  late final UserService userService;
  late final CallController callController;
  late final GroupCallController groupCallController;

  User? currentUser;
  bool isInitializing = true;
  bool authBusy = false;
  bool isDark = false;
  String? authError;
  String? profileError;

  Future<void> initialize() async {
    isInitializing = true;
    notifyListeners();

    try {
      final preferences = await SharedPreferences.getInstance();
      isDark = preferences.getBool(_darkModeKey) ?? false;

      if (await authService.hasSession()) {
        try {
          currentUser = await userService.getMe();
          await callController.connect(currentUser!);
          await groupCallController.connect(currentUser!);
        } catch (_) {
          currentUser = null;
          await authService.clearLocalSession();
        }
      }
    } catch (_) {
      currentUser = null;
      authError = 'Không thể khôi phục phiên đăng nhập trên thiết bị này.';
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String username, String password) async {
    if (authBusy) return false;
    authBusy = true;
    authError = null;
    notifyListeners();

    try {
      await authService.signIn(username: username, password: password);
      currentUser = await userService.getMe();
      await callController.connect(currentUser!);
      await groupCallController.connect(currentUser!);
      return true;
    } catch (error) {
      currentUser = null;
      authError = _messageFor(
        error,
        fallback: 'Đăng nhập không thành công. Vui lòng thử lại.',
      );
      await authService.clearLocalSession();
      return false;
    } finally {
      authBusy = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() async {
    if (authBusy) return false;
    authBusy = true;
    authError = null;
    notifyListeners();

    try {
      await authService.signInWithGoogle();
      currentUser = await userService.getMe();
      await callController.connect(currentUser!);
      await groupCallController.connect(currentUser!);
      return true;
    } catch (error) {
      currentUser = null;
      authError = _messageFor(
        error,
        fallback: 'Đăng nhập bằng Google không thành công.',
      );
      await authService.clearLocalSession();
      return false;
    } finally {
      authBusy = false;
      notifyListeners();
    }
  }

  Future<bool> signUp({
    required String username,
    required String password,
    required String email,
    required String firstName,
    required String lastName,
  }) async {
    if (authBusy) return false;
    authBusy = true;
    authError = null;
    notifyListeners();

    try {
      await authService.signUp(
        username: username,
        password: password,
        email: email,
        firstName: firstName,
        lastName: lastName,
      );
      return true;
    } catch (error) {
      authError = _messageFor(
        error,
        fallback: 'Đăng ký không thành công. Vui lòng thử lại.',
      );
      return false;
    } finally {
      authBusy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (authBusy) return;
    authBusy = true;
    authError = null;
    notifyListeners();
    try {
      await callController.disconnect();
      await groupCallController.disconnect();
      await authService.signOut();
    } catch (error) {
      authError = _messageFor(
        error,
        fallback: 'Đã đăng xuất khỏi thiết bị, nhưng máy chủ chưa phản hồi.',
      );
    } finally {
      currentUser = null;
      authBusy = false;
      notifyListeners();
    }
  }

  Future<void> refreshCurrentUser() async {
    currentUser = await userService.getMe();
    notifyListeners();
  }

  Future<bool> updateAvatar(XFile image) async {
    if (profileError != null) profileError = null;
    try {
      final avatarUrl = await userService.uploadAvatar(image.path);
      currentUser = currentUser?.copyWith(avatarUrl: avatarUrl);
      notifyListeners();
      return true;
    } catch (error) {
      profileError = _messageFor(
        error,
        fallback: 'Không thể cập nhật ảnh đại diện.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfile({
    required String displayName,
    required String username,
    required String email,
    required String phone,
    required String bio,
  }) async {
    profileError = null;
    try {
      currentUser = await userService.updateProfile(
        displayName: displayName,
        username: username,
        email: email,
        phone: phone,
        bio: bio,
      );
      notifyListeners();
      return true;
    } catch (error) {
      profileError = _messageFor(error, fallback: 'Không thể cập nhật hồ sơ.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updatePreferences({
    bool? showOnlineStatus,
    bool? notificationsEnabled,
  }) async {
    profileError = null;
    try {
      currentUser = await userService.updatePreferences(
        showOnlineStatus: showOnlineStatus,
        notificationsEnabled: notificationsEnabled,
      );
      notifyListeners();
      return true;
    } catch (error) {
      profileError = _messageFor(
        error,
        fallback: 'Không thể cập nhật cấu hình.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    profileError = null;
    try {
      await userService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return true;
    } catch (error) {
      profileError = _messageFor(error, fallback: 'Không thể đổi mật khẩu.');
      notifyListeners();
      return false;
    }
  }

  Future<void> toggleTheme() async {
    isDark = !isDark;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_darkModeKey, isDark);
  }

  void clearAuthError() {
    if (authError == null) return;
    authError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    callController.dispose();
    groupCallController.dispose();
    super.dispose();
  }

  static String _messageFor(Object error, {required String fallback}) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return fallback;
  }
}
