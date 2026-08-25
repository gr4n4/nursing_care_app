import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// enableOnThisDevice() 결과. 권한 거부와 토큰 발급 실패(타임아웃 등)는
/// 사용자에게 다른 안내를 보여줘야 해서 하나의 bool로 뭉치지 않는다.
enum EnableResult { success, permissionDenied, tokenFailed }

/// 기록 누락 푸시 알림(FCM)의 기기 등록 담당.
///
/// 흐름: 브라우저/기기에서 알림 권한 → FCM 토큰 발급 → Firestore `push_tokens`에 저장
///      → (별도) GitHub Actions 스케줄러가 이 토큰들로 발송.
///
/// 토큰을 users 문서 배열이 아니라 별도 컬렉션에 두는 이유:
/// 스케줄러가 만료·해지된 토큰을 문서 하나 삭제로 정리할 수 있고,
/// 토큰 전체를 한 번의 쿼리로 읽을 수 있어 Firestore 무료 할당량에 유리하다.
class PushMessaging {
  /// Firebase 콘솔 > 프로젝트 설정 > 클라우드 메시징 > 웹 푸시 인증서의 공개 키.
  /// 공개값이라 클라이언트에 그대로 들어가도 된다.
  static const String vapidKey =
      'BBXE879aU7iZCK-Xw8Yt51u07UviyCqyw_nE3NpOLr-rgwvLxzTqQQu26XqOpS7mK9dcaSY5W_QGnZmahZRCXxM';

  static CollectionReference<Map<String, dynamic>> get _tokens =>
      FirebaseFirestore.instance.collection('push_tokens');

  /// 마지막으로 실패한 단계와 원인. 폰의 릴리즈 빌드에서는 콘솔 로그를 볼 수 없어서
  /// 화면에 그대로 띄우기 위해 남긴다(진단용).
  static String? lastError;

  /// 지금 이 기기의 알림 권한 상태.
  static Future<AuthorizationStatus> permissionStatus() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus;
  }

  /// 화면에 보여줄 권한 상태 문구.
  static Future<String> permissionLabel() async {
    try {
      final status = await permissionStatus();
      return status.name;
    } catch (e) {
      return '확인 실패: $e';
    }
  }

  /// 권한을 이미 받아 둔 기기에서만 조용히 토큰을 갱신한다.
  /// 앱을 열 때마다 호출해도 권한 팝업이 뜨지 않는다(로그인 직후 호출용).
  static Future<String?> refreshQuietly(String email) async {
    final status = await permissionStatus();
    if (status != AuthorizationStatus.authorized &&
        status != AuthorizationStatus.provisional) {
      return null;
    }
    return _saveToken(email);
  }

  /// 설정 화면의 "이 기기에서 알림 받기" 버튼용.
  /// 권한 팝업은 브라우저가 사용자 조작을 요구하므로 반드시 버튼에서 호출한다.
  static Future<EnableResult> enableOnThisDevice(String email) async {
    lastError = null;

    final AuthorizationStatus status;
    try {
      final settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true)
          .timeout(const Duration(seconds: 60));
      status = settings.authorizationStatus;
    } on TimeoutException {
      lastError = '권한 요청 응답 없음 — 브라우저 알림 팝업이 뜨지 않았을 수 있습니다.';
      return EnableResult.tokenFailed;
    } catch (e) {
      lastError = 'requestPermission() 실패: $e';
      return EnableResult.tokenFailed;
    }

    if (status != AuthorizationStatus.authorized &&
        status != AuthorizationStatus.provisional) {
      lastError = '권한 상태: ${status.name}';
      return EnableResult.permissionDenied;
    }

    final token = await _saveToken(email);
    return token != null ? EnableResult.success : EnableResult.tokenFailed;
  }

  /// 이 기기에서 알림을 끈다. 토큰 문서를 지우면 스케줄러가 더는 보내지 않는다.
  /// (브라우저 권한 자체는 앱에서 회수할 수 없어 사용자가 사이트 설정에서 꺼야 한다.)
  static Future<void> disableOnThisDevice() async {
    final token = await _currentToken();
    if (token == null) return;
    await _tokens.doc(token).delete();
  }

  /// 이 기기 토큰이 서버에 등록돼 있는지.
  /// 권한이 없으면 getToken()이 어차피 실패하므로 아예 호출하지 않는다
  /// (설정 화면을 열 때마다 20초씩 기다리는 것을 막는다).
  static Future<bool> isRegistered() async {
    try {
      final status = await permissionStatus();
      if (status != AuthorizationStatus.authorized &&
          status != AuthorizationStatus.provisional) {
        return false;
      }
      final token = await _currentToken();
      if (token == null) return false;
      final doc = await _tokens.doc(token).get();
      return doc.exists;
    } catch (e) {
      lastError = '등록 상태 확인 실패: $e';
      return false;
    }
  }

  /// 서비스워커가 이 탭을 아직 장악(activate)하지 못했거나 네트워크가 느리면
  /// getToken()이 응답 없이 멈출 수 있다. 무한정 기다리지 않고 타임아웃으로
  /// 끊어서, 화면이 "처리 중"에 영원히 갇히는 대신 실패로 안내되게 한다.
  static Future<String?> _currentToken() async {
    try {
      final token = await FirebaseMessaging.instance
          .getToken(vapidKey: kIsWeb ? vapidKey : null)
          .timeout(const Duration(seconds: 20));
      if (token == null) {
        lastError = 'getToken()이 null을 반환했습니다.';
      }
      return token;
    } on TimeoutException {
      lastError = 'getToken() 20초 타임아웃 — 서비스워커가 활성화되지 않았을 수 있습니다.';
      debugPrint('FCM 토큰 조회 타임아웃');
      return null;
    } catch (e) {
      lastError = 'getToken() 실패: $e';
      debugPrint('FCM 토큰 조회 실패: $e');
      return null;
    }
  }

  static Future<String?> _saveToken(String email) async {
    final token = await _currentToken();
    if (token == null) return null;

    // Firestore 쓰기도 실패할 수 있다(보안 규칙 거부, 오프라인 등).
    // 여기서 예외가 새어 나가면 호출한 화면이 '처리 중'에서 멈추므로 반드시 잡는다.
    try {
      // 문서 ID = 토큰. 같은 기기에서 여러 번 호출해도 문서가 늘지 않는다.
      await _tokens.doc(token).set({
        'email': email,
        'token': token,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));

      return token;
    } on TimeoutException {
      lastError = 'push_tokens 저장 15초 타임아웃 (네트워크 확인 필요)';
      return null;
    } catch (e) {
      lastError = 'push_tokens 저장 실패: $e';
      debugPrint('토큰 저장 실패: $e');
      return null;
    }
  }

  /// 앱이 화면에 떠 있을 때(foreground) 도착하는 메시지를 화면 안 배너로 보여준다.
  ///
  /// FCM 웹은 탭이 백그라운드일 때만 서비스워커가 시스템 알림을 띄운다.
  /// 탭이 포커스된 상태로 오는 메시지는 onMessage 로 들어오고, 여기서 받지 않으면
  /// 아무 데도 표시되지 않고 그대로 사라진다(간호사가 알림을 놓치게 된다).
  static bool _foregroundListenerAttached = false;

  static void listenForegroundMessages(GlobalKey<NavigatorState> navigatorKey) {
    // AuthGate의 FutureBuilder는 재빌드 때마다 이 함수를 다시 부를 수 있다.
    // 그때마다 구독을 추가하면 배너가 여러 번 겹쳐 뜬다.
    if (_foregroundListenerAttached) return;
    _foregroundListenerAttached = true;

    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      final title = (data['title'] ?? message.notification?.title ?? 'Balancare')
          .toString();
      final body = (data['body'] ?? message.notification?.body ?? '').toString();

      final context = navigatorKey.currentContext;
      if (context == null) return;

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;

      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                color: Color(0xFF7CCFC6),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  static bool _tokenRefreshListenerAttached = false;

  /// 토큰이 갱신되면(브라우저가 주기적으로 교체) 새 토큰을 다시 저장한다.
  /// 옛 토큰 문서는 스케줄러가 발송 실패 시 정리한다.
  static void listenTokenRefresh(String email) {
    // foreground 리스너와 같은 이유로 중복 구독을 막는다.
    if (_tokenRefreshListenerAttached) return;
    _tokenRefreshListenerAttached = true;

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      try {
        await _tokens.doc(token).set({
          'email': email,
          'token': token,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'updatedAt': Timestamp.now(),
        }, SetOptions(merge: true));
      } catch (e) {
        // 백그라운드 갱신이라 실패해도 화면을 막을 수 없다. 다음 로그인 때 다시 저장된다.
        debugPrint('토큰 갱신 저장 실패: $e');
      }
    });
  }
}
