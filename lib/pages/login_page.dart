import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'station_page.dart';
import 'nurse_register_page.dart';
import 'nurse_home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color mint = Color(0xFF7CCFC6);
  static const Color mintDark = Color(0xFF0F766E);
  static const Color mintSoft = Color(0xFFEAF8F6);
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color borderGrey = Color(0xFFE5E7EB);

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final FocusNode emailFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();

  bool isLoading = false;

  String stringField(Map<String, dynamic> data, String key) {
    return (data[key] ?? '').toString().trim();
  }

  Future<void> login() async {
    if (isLoading) return;

    FocusScope.of(context).unfocus();

    // 좁은 화면(폰/홈화면 PWA)=간호사 입력 앱, 넓은 화면(데스크톱)=대시보드.
    final bool wideLayout = MediaQuery.of(context).size.width >= 900;

    setState(() {
      isLoading = true;
    });

    try {
      final email = emailController.text.trim().toLowerCase();
      final password = passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        throw Exception('이메일과 비밀번호를 입력해주세요.');
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        throw Exception('사용자 권한 정보가 없습니다.');
      }

      final data = userDoc.data()!;

      final role = stringField(data, 'role');

      if (!mounted) return;

      if (role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const StationPage(),
          ),
        );
        return;
      }

      if (role == 'nurse') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                wideLayout ? const StationPage() : const NurseHomePage(),
          ),
        );
        return;
      }

      await FirebaseAuth.instance.signOut();
      throw Exception('알 수 없는 권한입니다: $role');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그인 오류: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> resetPassword() async {
    String inputEmail = emailController.text.trim().toLowerCase();

    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('비밀번호 재설정'),
          content: TextField(
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: '가입한 이메일',
              hintText: 'example@email.com',
              prefixIcon: const Icon(Icons.email_outlined),
              border: const OutlineInputBorder(),
              helperText: inputEmail.isEmpty ? null : '현재 입력값이 자동으로 채워졌습니다.',
            ),
            controller: TextEditingController(text: inputEmail),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (inputEmail.isNotEmpty) {
                Navigator.of(dialogContext).pop(inputEmail);
              }
            },
            onChanged: (value) {
              inputEmail = value.trim().toLowerCase();
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                if (inputEmail.isEmpty) {
                  return;
                }

                Navigator.of(dialogContext).pop(inputEmail);
              },
              child: const Text('발송'),
            ),
          ],
        );
      },
    );

    if (email == null || email.isEmpty) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('가입된 이메일이라면 비밀번호 재설정 메일이 발송됩니다.'),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message = '비밀번호 재설정 메일 발송에 실패했습니다.';

      if (e.code == 'invalid-email') {
        message = '이메일 형식이 올바르지 않습니다.';
      } else if (e.code == 'network-request-failed') {
        message = '네트워크 연결을 확인해주세요.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('비밀번호 재설정 오류: $e')),
      );
    }
  }

  void goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NurseRegisterPage(),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  Widget logoMark() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: mint.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Icon(
        Icons.local_hospital_rounded,
        size: 38,
        color: Color(0xFF3AAFA9),
      ),
    );
  }

  ButtonStyle primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: mintDark,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      textStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  ButtonStyle outlineButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: mintDark,
      side: const BorderSide(color: mintDark, width: 1.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  InputDecoration inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: mintDark, width: 1.5),
      ),
    );
  }

  Widget platformGuide(bool wide) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGrey),
      ),
      child: Text(
        wide
            ? '넓은 화면에서는 관리자·통합 대시보드로 이용합니다.'
            : '홈 화면에 추가해 앱처럼 사용하세요. 간호사는 환자를 선택해 식사량·배설량을 기록합니다.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          height: 1.35,
          color: Color(0xFF9CA3AF),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: mintSoft,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: mintSoft,
        elevation: 0,
        surfaceTintColor: mintSoft,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              elevation: 8,
              shadowColor: Colors.black12,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: const BorderSide(
                  color: borderGrey,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    logoMark(),
                    const SizedBox(height: 20),
                    const Text(
                      'Care Note',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '식사 · 수분 · 배설 통합 관리',
                      style: TextStyle(
                        fontSize: 15,
                        color: textGrey,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: emailController,
                      focusNode: emailFocusNode,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      enabled: !isLoading,
                      decoration: inputDecoration(
                        label: '이메일',
                        icon: Icons.email_outlined,
                      ),
                      onSubmitted: (_) {
                        passwordFocusNode.requestFocus();
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      focusNode: passwordFocusNode,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      enabled: !isLoading,
                      decoration: inputDecoration(
                        label: '비밀번호',
                        icon: Icons.lock_outline,
                      ),
                      onSubmitted: (_) {
                        if (!isLoading) {
                          login();
                        }
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isLoading ? null : resetPassword,
                        child: const Text('비밀번호를 잊으셨나요?'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: primaryButtonStyle(),
                        onPressed: isLoading ? null : login,
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('로그인'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        style: outlineButtonStyle(),
                        onPressed: isLoading ? null : goToRegister,
                        child: const Text('간호사 가입'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    platformGuide(MediaQuery.of(context).size.width >= 900),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}