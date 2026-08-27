import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 간호사가 환자를 등록하는 화면.
/// 환자는 로그인 계정이 아니라 patients 컬렉션의 문서로만 존재한다.
class PatientRegisterPage extends StatefulWidget {
  const PatientRegisterPage({super.key});

  @override
  State<PatientRegisterPage> createState() => _PatientRegisterPageState();
}

class _PatientRegisterPageState extends State<PatientRegisterPage> {
  static const Color mintDark = Color(0xFF16305E);
  static const Color mintSoft = Color(0xFFDCE7F5);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);

  final nameController = TextEditingController();
  final birthDateController = TextEditingController();
  final roomController = TextEditingController();
  final heightController = TextEditingController();
  final weightController = TextEditingController();
  final noteController = TextEditingController();

  String gender = 'male'; // 'male' | 'female'
  bool isSaving = false;

  String normalizeBirthDate(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return '';

    final onlyDigits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (onlyDigits.length != 8) {
      throw Exception('생년월일은 19980101 또는 1998-01-01 형식으로 입력해주세요.');
    }

    final year = int.tryParse(onlyDigits.substring(0, 4));
    final month = int.tryParse(onlyDigits.substring(4, 6));
    final day = int.tryParse(onlyDigits.substring(6, 8));

    if (year == null || month == null || day == null) {
      throw Exception('생년월일 형식이 올바르지 않습니다.');
    }

    final parsed = DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}',
    );

    if (parsed == null ||
        parsed.year != year ||
        parsed.month != month ||
        parsed.day != day) {
      throw Exception('존재하지 않는 날짜입니다. 다시 입력해주세요.');
    }

    final today = DateTime.now();
    if (DateTime(year, month, day)
        .isAfter(DateTime(today.year, today.month, today.day))) {
      throw Exception('생년월일은 오늘 이후 날짜로 입력할 수 없습니다.');
    }

    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  Future<void> save() async {
    if (isSaving) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('환자 이름을 입력해주세요.')),
      );
      return;
    }

    String birthDate;
    try {
      birthDate = normalizeBirthDate(birthDateController.text);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    // 등록한 간호사를 담당(assignedNurses)으로 자동 배정 → 그 간호사의 "내 환자"에 뜬다.
    final creatorEmail =
        FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '';

    try {
      await FirebaseFirestore.instance.collection('patients').add({
        'name': name,
        'gender': gender,
        'birthDate': birthDate,
        // "302호"처럼 입력해도 '호'는 표시할 때 붙이므로 저장 시 제거해 중복을 막는다.
        'room': roomController.text.trim().replaceAll('호', '').trim(),
        'heightCm': int.tryParse(heightController.text.trim()) ?? 0,
        'weightKg': int.tryParse(weightController.text.trim()) ?? 0,
        'note': noteController.text.trim(),
        'isActive': true,
        'assignedNurses': creatorEmail.isEmpty ? <String>[] : [creatorEmail],
        'createdAt': Timestamp.now(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name 환자를 등록했습니다.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('환자 등록 오류: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    birthDateController.dispose();
    roomController.dispose();
    heightController.dispose();
    weightController.dispose();
    noteController.dispose();
    super.dispose();
  }

  double contentMaxWidth(double screenWidth) {
    if (kIsWeb && screenWidth >= 900) return 760;
    if (screenWidth >= 700) return 560;
    return screenWidth;
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
                  width: 168,
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
            '새 환자 등록',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '환자 정보를 입력하면 목록에 추가됩니다.',
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

  InputDecoration inputDecoration({required String label, String? hintText}) {
    return InputDecoration(
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
    );
  }

  Widget inputField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        enabled: !isSaving,
        decoration: inputDecoration(label: label, hintText: hintText),
      ),
    );
  }

  Widget genderSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '성별',
              style: TextStyle(color: textGrey, fontSize: 13),
            ),
          ),
          Row(
            children: [
              genderOption(label: '남', value: 'male'),
              const SizedBox(width: 12),
              genderOption(label: '여', value: 'female'),
            ],
          ),
        ],
      ),
    );
  }

  Widget genderOption({required String label, required String value}) {
    final selected = gender == value;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isSaving ? null : () => setState(() => gender = value),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? mintSoft : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? mintDark : borderGrey,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? mintDark : textGrey,
              fontSize: 16,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
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
                                  controller: nameController, label: '환자 이름'),
                              genderSelector(),
                              inputField(
                                controller: birthDateController,
                                label: '생년월일 (선택)',
                                hintText: '예: 19980101 또는 1998-01-01',
                                keyboardType: TextInputType.datetime,
                              ),
                              inputField(
                                  controller: roomController,
                                  label: '병실 위치',
                                  hintText: '예: 신관 219호'),
                              inputField(
                                controller: heightController,
                                label: '키(cm)',
                                keyboardType: TextInputType.number,
                              ),
                              inputField(
                                controller: weightController,
                                label: '몸무게(kg)',
                                keyboardType: TextInputType.number,
                              ),
                              inputField(
                                controller: noteController,
                                label: '특이사항 / 주의사항',
                                maxLines: 3,
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 54,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: mintDark,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: isSaving ? null : save,
                                  child: isSaving
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          '환자 등록',
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
