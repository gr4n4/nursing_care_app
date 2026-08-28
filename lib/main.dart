import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'theme/app_colors.dart';
import 'utils/alert_center.dart';
import 'utils/push_messaging.dart';
import 'pages/login_page.dart';
import 'pages/station_page.dart';
import 'pages/nurse_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 로그인 유지. 웹 기본값도 이렇지만, 기본값에 기대면 나중에 조용히 바뀔 수 있어
  // 명시한다. 간호사들이 매번 로그인하지 않아도 되게 하는 것이 목적.
  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    } catch (e) {
      debugPrint('로그인 유지 설정 실패: $e');
    }
  }

  // 읽은 데이터를 기기에 캐시한다.
  //
  // 켜기 전에는 화면을 열 때마다 네트워크 왕복을 기다렸다. 병동 와이파이가
  // 느려 그 대기가 그대로 체감됐다. 캐시가 있으면 저장된 값을 먼저 그려 놓고
  // 서버 응답이 오면 갱신하므로 두 번째부터는 즉시 뜬다.
  //
  // 실패해도 앱은 그냥 네트워크로 동작하면 되므로 막지 않는다.
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Firestore 캐시 설정 실패: $e');
  }

  runApp(const CareNoteApp());
}

class CareNoteApp extends StatelessWidget {
  const CareNoteApp({super.key});

  /// 앱이 화면에 떠 있을 때 도착하는 푸시를 배너로 띄우려면
  /// 위젯 트리 밖에서도 쓸 수 있는 context가 필요하다.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NRCarec',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // 화면을 손가락으로 밀어 뒤로 가기.
        //
        // 기본값은 플랫폼에 따라 갈리고, 웹에서는 안드로이드 전환이 잡혀
        // 밀기 제스처가 아예 없다. 아이폰 홈화면 PWA로 쓰는 환경이라
        // 모든 플랫폼에서 Cupertino 전환을 써 밀기 뒤로가기를 켠다.
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
            TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
            TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
          },
        ),
        scaffoldBackgroundColor: AppColors.pageBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF111827),
          centerTitle: false,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFFE5E7EB),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.interactive,
              width: 2,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      // 모든 화면을 감싸 왼쪽 가장자리 밀기를 받는다.
      builder: (context, child) => _EdgeSwipeBack(child: child),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

/// 첫 화면에서 뒤로가기를 막아야 하는 환경인가.
///
/// iOS 홈화면 PWA 는 브라우저 UI 가 없어, 첫 화면에서 더 뒤로 가면 앱 이전의
/// 빈 기록으로 빠져나가 흰 화면에 갇힌다. 그래서 막아야 한다.
///
/// 안드로이드는 다르다. 뒤로가기가 시스템 기본 조작이라 첫 화면에서 누르면
/// 앱이 닫히는 것이 정상이고, 그렇게 나가도 런처로 돌아갈 뿐 흰 화면이 아니다.
/// 여기서 막으면 오히려 앱이 갇힌 것처럼 느껴진다.
bool get blockRootBack =>
    kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class _AuthGateState extends State<AuthGate> {
  /// 시작 화면 판별 결과를 캐시한다.
  ///
  /// 전에는 build 안에서 future 를 새로 만들고 MediaQuery 까지 읽어서,
  /// 키보드가 뜨거나 창 크기가 바뀔 때마다 Firestore 를 다시 읽고 화면을
  /// 통째로 새로 만들었다. 로그인 직후와 화면 전환이 느렸던 원인.
  Future<Widget>? _startPage;
  String? _forUid;

  /// 시작 화면 판별을 처음부터 다시 한다. 오류 화면의 '다시 시도'가 쓴다.
  void retryStartup() {
    if (!mounted) return;
    setState(() {
      _startPage = null;
      _forUid = null;
    });
  }

  Future<Widget> getStartPage(User user, bool wide) async {
    final email = user.email;

    if (email == null) {
      return const LoginPage();
    }

    // 권한 조회가 실패해도 로그아웃시키지 않는다.
    //
    // 전에는 실패하면 예외가 그대로 올라가 로딩 표시에서 멈췄고, 문서를 못 읽으면
    // 곧장 로그아웃시켰다. 병동 와이파이가 잠깐 끊긴 것뿐인데 다시 로그인해야 해서
    // 곤란하다. 네트워크 문제와 '권한이 정말 없는 경우'를 갈라서 처리한다.
    final DocumentSnapshot<Map<String, dynamic>> userDoc;
    try {
      userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .get()
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      return _StartupErrorPage(
        message: '연결이 원활하지 않아 계정 정보를 불러오지 못했습니다. '
            '로그인은 유지되어 있으니 잠시 후 다시 시도해 주세요.',
        detail: '$e',
        onRetry: retryStartup,
      );
    }

    if (!userDoc.exists) {
      await FirebaseAuth.instance.signOut();
      return const LoginPage();
    }

    final data = userDoc.data()!;
    final role = (data['role'] ?? '').toString().trim();

    // 이미 알림을 허용한 기기면 토큰만 조용히 갱신한다(권한 팝업 없음).
    // 최초 허용은 알림 설정 화면의 버튼에서 받는다 — 브라우저가 사용자 조작을 요구한다.
    unawaited(
      PushMessaging.refreshQuietly(email).catchError((Object e) {
        debugPrint('FCM 토큰 갱신 건너뜀: $e');
        return null;
      }),
    );
    PushMessaging.listenTokenRefresh(email);
    // 탭이 포커스된 상태로 오는 푸시는 서비스워커가 아니라 앱으로 들어온다.
    // 받아서 배너로 띄우지 않으면 아무 데도 안 보이고 사라진다.
    PushMessaging.listenForegroundMessages(CareNoteApp.navigatorKey);
    // 낙상·걸터앉음 경보 구독. 앱·대시보드가 열려 있으면 즉시 소리와 팝업으로 알린다.
    AlertCenter.start(CareNoteApp.navigatorKey);

    // 좁은 화면(폰/홈화면 PWA)은 간호사 입력 앱, 넓은 화면(데스크톱)은 대시보드로.
    if (role == 'nurse') {
      return wide ? const StationPage() : const NurseHomePage();
    }

    if (role == 'admin') {
      return const StationPage();
    }

    await FirebaseAuth.instance.signOut();
    return const LoginPage();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = authSnapshot.data;

        if (user == null) {
          _startPage = null;
          _forUid = null;
          // 로그인 화면도 첫 화면이라 뒤로 갈 곳이 없다.
          return PopScope(canPop: !blockRootBack, child: const LoginPage());
        }

        // 같은 계정이면 판별을 다시 하지 않는다. 화면 크기는 여기서 한 번만 본다.
        if (_startPage == null || _forUid != user.uid) {
          _forUid = user.uid;
          final wide =
              MediaQueryData.fromView(View.of(context)).size.width >= 900;
          _startPage = getStartPage(user, wide);
        }

        return FutureBuilder<Widget>(
          future: _startPage,
          builder: (context, pageSnapshot) {
            if (!pageSnapshot.hasData) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            // 첫 화면에서 더 뒤로 가면 앱 이전의 빈 기록으로 빠져나가
            // 흰 화면만 남는다(iOS 홈화면 PWA는 브라우저 UI도 없어 갇힌다).
            return PopScope(
              canPop: !blockRootBack,
              child: pageSnapshot.data!,
            );
          },
        );
      },
    );
  }
}

/// 시작할 때 계정 정보를 못 읽었을 때 보여주는 화면.
///
/// 로그아웃시키지 않는 것이 핵심이다. 연결이 잠깐 끊긴 것뿐인데 로그인을 풀면
/// 병동에서 다시 아이디·비밀번호를 찾아 넣어야 한다.
class _StartupErrorPage extends StatelessWidget {
  final String message;
  final String detail;
  final VoidCallback onRetry;

  const _StartupErrorPage({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 46,
                  color: AppColors.inkDim,
                ),
                const SizedBox(height: 18),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('다시 시도'),
                  ),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.inkDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 화면 왼쪽을 오른쪽으로 밀면 뒤로 가게 한다.
///
/// Flutter 자체 밀기(Cupertino 전환)는 왼쪽 20px 만 감지하는데, iOS 홈화면 PWA
/// 에서는 바로 그 구간을 iOS 가 자기 기록 이동 제스처로 먼저 가져간다. 그러면
/// 앱이 아니라 브라우저 기록이 뒤로 가서 흰 화면이 됐다.
/// 그보다 안쪽까지(48px) 우리가 받아, 시스템이 채가지 않은 밀기를 처리한다.
class _EdgeSwipeBack extends StatefulWidget {
  final Widget? child;

  const _EdgeSwipeBack({required this.child});

  @override
  State<_EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<_EdgeSwipeBack> {
  /// iOS 가 가져가는 구간보다 넉넉히 안쪽까지 잡는다.
  static const double _edgeWidth = 48;

  /// 이만큼 밀어야 뒤로 간다. 너무 짧으면 살짝 스친 것도 뒤로 가버린다.
  static const double _threshold = 60;

  /// 한 번 민 동작에서 여러 장이 닫히지 않게 잠근다.
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (widget.child != null) widget.child!,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _edgeWidth,
          // 세로 스크롤과 탭은 그대로 아래로 통과시키고, 가로로 미는 것만 잡는다.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _handled = false,
            onHorizontalDragUpdate: (details) {
              if (_handled) return;
              if (details.localPosition.dx > _threshold) _pop(context);
            },
            onHorizontalDragEnd: (details) {
              if (_handled) return;
              // 짧게 튕기듯 민 경우도 받아준다.
              if ((details.primaryVelocity ?? 0) > 300) _pop(context);
            },
          ),
        ),
      ],
    );
  }

  void _pop(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) return;
    // 첫 화면이면 나갈 곳이 없다. 여기서 막지 않으면 흰 화면이 된다.
    if (!navigator.canPop()) return;
    _handled = true;
    navigator.maybePop();
  }
}
