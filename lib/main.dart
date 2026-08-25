import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'utils/push_messaging.dart';
import 'pages/login_page.dart';
import 'pages/station_page.dart';
import 'pages/nurse_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
      title: 'Balancare',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7CCFC6),
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
              color: Color(0xFF7CCFC6),
              width: 2,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7CCFC6),
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
          return const LoginPage();
        }

        return FutureBuilder<Widget>(
          future: getStartPage(user, MediaQuery.of(context).size.width >= 900),
          builder: (context, pageSnapshot) {
            if (!pageSnapshot.hasData) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            return pageSnapshot.data!;
          },
        );
      },
    );
  }
}