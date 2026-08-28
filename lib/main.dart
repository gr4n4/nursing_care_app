import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'theme/app_colors.dart';
import 'utils/push_messaging.dart';
import 'pages/login_page.dart';
import 'pages/station_page.dart';
import 'pages/nurse_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// 시작 화면 판별 결과를 캐시한다.
  ///
  /// 전에는 build 안에서 future 를 새로 만들고 MediaQuery 까지 읽어서,
  /// 키보드가 뜨거나 창 크기가 바뀔 때마다 Firestore 를 다시 읽고 화면을
  /// 통째로 새로 만들었다. 로그인 직후와 화면 전환이 느렸던 원인.
  Future<Widget>? _startPage;
  String? _forUid;

  Future<Widget> getStartPage(User user, bool wide) async {
    final email = user.email;

    if (email == null) {
      return const LoginPage();
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(email)
        .get();

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
          return const PopScope(canPop: false, child: LoginPage());
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
              canPop: false,
              child: pageSnapshot.data!,
            );
          },
        );
      },
    );
  }
}
