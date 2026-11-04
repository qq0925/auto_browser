import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 负责网站 Cookie 提取、多账号配置存储与切换的服务类
class CookieService {
  static final CookieManager _cookieManager = CookieManager.instance();
  static const String _profilesKey = 'saved_cookie_profiles';

  /// 获取指定 URL 下的所有 Cookie
  static Future<List<Cookie>> getCookies(String urlString) async {
    try {
      final uri = WebUri(urlString);
      return await _cookieManager.getCookies(url: uri);
    } catch (e) {
      debugPrint('获取 Cookie 失败: $e');
      return [];
    }
  }

  /// 设置单个 Cookie
  static Future<bool> setCookie({
    required String urlString,
    required String name,
    required dynamic value,
    String? domain,
    String path = '/',
    int? expiresDate,
    bool? isSecure,
    bool? isHttpOnly,
  }) async {
    try {
      final uri = WebUri(urlString);
      return await _cookieManager.setCookie(
        url: uri,
        name: name,
        value: value,
        domain: domain,
        path: path,
        expiresDate: expiresDate,
        isSecure: isSecure,
        isHttpOnly: isHttpOnly,
      );
    } catch (e) {
      debugPrint('设置 Cookie 失败: $e');
      return false;
    }
  }

  /// 清除指定 URL 下的 Cookie
  static Future<bool> clearCookiesForUrl(String urlString) async {
    try {
      final uri = WebUri(urlString);
      return await _cookieManager.deleteCookies(url: uri);
    } catch (e) {
      debugPrint('清除 Cookie 失败: $e');
      return false;
    }
  }

  /// 清除全部 Cookie
  static Future<bool> clearAllCookies() async {
    try {
      return await _cookieManager.deleteAllCookies();
    } catch (e) {
      debugPrint('清除全部 Cookie 失败: $e');
      return false;
    }
  }

  /// 保存当前站点的 Cookie 为多账号存档
  static Future<bool> saveProfile({
    required String profileName,
    required String domain,
    required List<Cookie> cookies,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = prefs.getString(_profilesKey);
      Map<String, dynamic> profiles = {};
      if (profilesJson != null && profilesJson.isNotEmpty) {
        profiles = jsonDecode(profilesJson) as Map<String, dynamic>;
      }

      final cookieDataList = cookies.map((c) => {
            'name': c.name,
            'value': c.value,
            'domain': c.domain,
            'path': c.path ?? '/',
            'expiresDate': c.expiresDate,
            'isSecure': c.isSecure,
            'isHttpOnly': c.isHttpOnly,
          }).toList();

      profiles[profileName] = {
        'profileName': profileName,
        'domain': domain,
        'createdAt': DateTime.now().toIso8601String(),
        'cookies': cookieDataList,
      };

      return await prefs.setString(_profilesKey, jsonEncode(profiles));
    } catch (e) {
      debugPrint('保存 Cookie 存档失败: $e');
      return false;
    }
  }

  /// 获取所有已保存的账号存档（可按 domain 过滤）
  static Future<List<Map<String, dynamic>>> getSavedProfiles({String? domain}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = prefs.getString(_profilesKey);
      if (profilesJson == null || profilesJson.isEmpty) return [];

      final profiles = jsonDecode(profilesJson) as Map<String, dynamic>;
      final list = profiles.values.cast<Map<String, dynamic>>().toList();

      if (domain != null && domain.isNotEmpty) {
        return list.where((p) {
          final pDomain = p['domain'] as String? ?? '';
          return pDomain.contains(domain) || domain.contains(pDomain);
        }).toList();
      }

      return list;
    } catch (e) {
      debugPrint('获取 Cookie 存档列表失败: $e');
      return [];
    }
  }

  /// 删除指定的账号存档
  static Future<bool> deleteProfile(String profileName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = prefs.getString(_profilesKey);
      if (profilesJson == null || profilesJson.isEmpty) return false;

      final profiles = jsonDecode(profilesJson) as Map<String, dynamic>;
      profiles.remove(profileName);
      return await prefs.setString(_profilesKey, jsonEncode(profiles));
    } catch (e) {
      debugPrint('删除 Cookie 存档失败: $e');
      return false;
    }
  }

  /// 一键应用已保存的账号存档到当前 WebView
  static Future<bool> applyProfile({
    required String profileName,
    required String urlString,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = prefs.getString(_profilesKey);
      if (profilesJson == null || profilesJson.isEmpty) return false;

      final profiles = jsonDecode(profilesJson) as Map<String, dynamic>;
      final profileData = profiles[profileName] as Map<String, dynamic>?;
      if (profileData == null) return false;

      final uri = WebUri(urlString);

      // 先清除当前站点的旧 Cookie
      await _cookieManager.deleteCookies(url: uri);

      // 写入新存档的 Cookie
      final cookieList = profileData['cookies'] as List<dynamic>? ?? [];
      for (final item in cookieList) {
        if (item is Map<String, dynamic>) {
          await _cookieManager.setCookie(
            url: uri,
            name: item['name'] as String,
            value: item['value'],
            domain: item['domain'] as String?,
            path: item['path'] as String? ?? '/',
            expiresDate: item['expiresDate'] as int?,
            isSecure: item['isSecure'] as bool?,
            isHttpOnly: item['isHttpOnly'] as bool?,
          );
        }
      }
      return true;
    } catch (e) {
      debugPrint('应用 Cookie 存档失败: $e');
      return false;
    }
  }
}
