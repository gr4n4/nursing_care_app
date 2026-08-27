import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'nurse_home_page.dart';

/// 간호사 가입 화면. (환자는 계정이 아니라 간호사가 등록하는 데이터)
/// 별도 승인 절차 없이 가입 즉시 간호사로 이용할 수 있다.
class NurseRegisterPage extends StatefulWidget {
  const NurseRegisterPage({super.key});

  @override
  State<NurseRegisterPage> createState() => _NurseRegisterPageState();
}

class _NurseRegisterPageState extends State<NurseRegisterPage> {
  static const Color mintDark = Color(0xFF16305E);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color borderGrey = Color(0xFFE5E7EB);

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final nurseNameController = TextEditingController();
  final assignedRoomsController = TextEditingController();
  final nursePhoneController = TextEditingController();

  bool isLoading = false;

  Future<void> register() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
    });

    User? createdUser;

    try {
      final email = emailController.text.trim().toLowerCase();
      final password = passwordController.text.trim();

      if (email.isEmpty) {
        throw Exception('이메일을 입력해주세요.');
      }

      if (password.length < 6) {
        throw Exception('비밀번호는 6자리 이상이어야 합니다.');
      }

      if (nurseNameController.text.trim().isEmpty) {
        throw Exception('간호사 이름을 입력해주세요.');
      }

      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      createdUser = credential.user;

      if (createdUser == null) {
        throw Exception('Firebase Auth 계정 생성에 실패했습니다.');
      }

      await FirebaseFirestore.instance.collection('users').doc(email).set({
        'uid': createdUser.uid,
        'email': email,
        'role': 'nurse',
        'name': nurseNameController.text.trim(),
        'assignedRooms': assignedRoomsController.text.trim(),
        'phone': nursePhoneController.text.trim(),
        'createdAt': Timestamp.now(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('간호사 가입이 완료되었습니다.'),
        ),
      );

      // 승인 절차가 없으므로 가입 즉시(이미 로그인된 상태) 홈으로 이동.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const NurseHomePage(),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      String message = '회원가입 오류가 발생했습니다.';

      if (e.code == 'email-already-in-use') {
        message = '이미 Firebase Auth에 가입된 이메일입니다.';
      } else if (e.code == 'invalid-email') {
        message = '이메일 형식이 올바르지 않습니다.';
      } else if (e.code == 'weak-password') {
        message = '비밀번호가 너무 약합니다. 6자리 이상 입력해주세요.';
      } else if (e.code == 'operation-not-allowed') {
        message = 'Firebase 이메일/비밀번호 로그인이 비활성화되어 있습니다.';
      } else if (e.code == 'network-request-failed') {
        message = '네트워크 연결을 확인해주세요.';
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (createdUser != null) {
        try {
          await createdUser.delete();
        } catch (_) {}
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('회원가입 오류: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();

    nurseNameController.dispose();
    assignedRoomsController.dispose();
    nursePhoneController.dispose();

    super.dispose();
  }

  double contentMaxWidth(double screenWidth) {
    if (kIsWeb && screenWidth >= 900) return 760;
    if (screenWidth >= 700) return 560;
    return screenWidth;
  }

  Widget inputField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        obscureText: obscureText,
        enabled: !isLoading,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: borderGrey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: mintDark, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF16305E), Color(0xFF22437C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(34),
          bottomRight: Radius.circular(34),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Image.asset(
                  'assets/icon/nrcarec_wordmark_white.png',
                  width: 142,
                  fit: BoxFit.contain,
                  // 그림을 못 읽어도 화면은 떠야 하므로 글자로 대체한다.
                  errorBuilder: (_, _, _) => const Text(
                    'NRCAREC',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '간호사 가입',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '가입 후 바로 이용할 수 있습니다.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderGrey),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = contentMaxWidth(constraints.maxWidth);

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                        child: sectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              inputField(
                                controller: emailController,
                                label: '이메일',
                                keyboardType: TextInputType.emailAddress,
                              ),
                              inputField(
                                controller: passwordController,
                                label: '비밀번호',
                                obscureText: true,
                              ),
                              const Divider(height: 32),
                              inputField(
                                controller: nurseNameController,
                                label: '간호사 이름',
                              ),
                              inputField(
                                controller: assignedRoomsController,
                                label: '담당 병동/병실',
                                hintText: '예: 재활병동 301호',
                              ),
                              inputField(
                                controller: nursePhoneController,
                                label: '연락처',
                                hintText: '예: 010-1234-5678',
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: mintDark,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: isLoading ? null : register,
                                  child: isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          '간호사 가입',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
