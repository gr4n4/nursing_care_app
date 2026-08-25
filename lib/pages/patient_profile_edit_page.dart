import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PatientProfileEditPage extends StatefulWidget {
  final String patientId;

  const PatientProfileEditPage({
    super.key,
    required this.patientId,
  });

  @override
  State<PatientProfileEditPage> createState() => _PatientProfileEditPageState();
}

class _PatientProfileEditPageState extends State<PatientProfileEditPage> {
  static const Color mintDark = Color(0xFF16305E);
  static const Color mintSoft = Color(0xFFDCE7F5);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);

  String gender = ''; // 'male' | 'female' | ''(미지정)

  final nameController = TextEditingController();
  final birthDateController = TextEditingController();
  final roomController = TextEditingController();
  final heightController = TextEditingController();
  final weightController = TextEditingController();
  final noteController = TextEditingController();

  final nameFocusNode = FocusNode();
  final birthDateFocusNode = FocusNode();
  final roomFocusNode = FocusNode();
  final heightFocusNode = FocusNode();
  final weightFocusNode = FocusNode();
  final noteFocusNode = FocusNode();

  bool isLoading = true;
  bool isSaving = false;

  String normalizeRoom(String value) {
    return value.trim().replaceAll('호', '');
  }

  String normalizeBirthDate(String input) {
    final raw = input.trim();

    if (raw.isEmpty) {
      return '';
    }

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

    final parsedDate = DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}',
    );

    if (parsedDate == null ||
        parsedDate.year != year ||
        parsedDate.month != month ||
        parsedDate.day != day) {
      throw Exception('존재하지 않는 날짜입니다. 다시 입력해주세요.');
    }

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final birthOnly = DateTime(year, month, day);

    if (birthOnly.isAfter(todayOnly)) {
      throw Exception('생년월일은 오늘 이후 날짜로 입력할 수 없습니다.');
    }

    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  Future<void> loadPatient() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patientId)
          .get();

      if (!doc.exists) {
        throw Exception('환자 정보를 찾을 수 없습니다.');
      }

      final data = doc.data()!;

      gender = (data['gender'] ?? '').toString();
      nameController.text = data['name']?.toString() ?? '';
      birthDateController.text = data['birthDate']?.toString() ?? '';
      roomController.text = normalizeRoom(data['room']?.toString() ?? '');
      heightController.text = (data['heightCm'] ?? '').toString();
      weightController.text = (data['weightKg'] ?? '').toString();
      noteController.text = data['note']?.toString() ?? '';

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('환자 정보 불러오기 오류: $e')),
      );
    }
  }

  Future<void> savePatient() async {
    if (isSaving) return;

    FocusScope.of(context).unfocus();

    final name = nameController.text.trim();
    final room = normalizeRoom(roomController.text);

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('환자 이름을 입력해주세요.')),
      );
      return;
    }

    String normalizedBirthDate = '';

    try {
      normalizedBirthDate = normalizeBirthDate(birthDateController.text);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patientId)
          .update({
        'name': name,
        'gender': gender,
        'birthDate': normalizedBirthDate,
        'room': room,
        'heightCm': int.tryParse(heightController.text.trim()) ?? 0,
        'weightKg': int.tryParse(weightController.text.trim()) ?? 0,
        'note': noteController.text.trim(),
        'updatedAt': Timestamp.now(),
      });

      birthDateController.text = normalizedBirthDate;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('환자 정보가 수정되었습니다.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('환자 정보 수정 오류: $e')),
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
  void initState() {
    super.initState();
    loadPatient();
  }

  @override
  void dispose() {
    nameController.dispose();
    birthDateController.dispose();
    roomController.dispose();
    heightController.dispose();
    weightController.dispose();
    noteController.dispose();

    nameFocusNode.dispose();
    birthDateFocusNode.dispose();
    roomFocusNode.dispose();
    heightFocusNode.dispose();
    weightFocusNode.dispose();
    noteFocusNode.dispose();

    super.dispose();
  }

  double contentMaxWidth(double screenWidth) {
    if (kIsWeb && screenWidth >= 900) return 760;
    if (screenWidth >= 700) return 560;
    return screenWidth;
  }

  InputDecoration inputDecoration({
    required String label,
    String? suffixText,
    String? hintText,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      suffixText: suffixText,
      prefixIcon: icon == null ? null : Icon(icon),
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
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderGrey),
      ),
    );
  }

  Widget inputField({
    required TextEditingController controller,
    required String label,
    required FocusNode focusNode,
    FocusNode? nextFocusNode,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? suffixText,
    String? hintText,
    IconData? icon,
    TextInputAction? textInputAction,
    VoidCallback? onDone,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        maxLines: maxLines,
        enabled: !isSaving,
        textInputAction: textInputAction ??
            (maxLines > 1
                ? TextInputAction.newline
                : (nextFocusNode == null
                    ? TextInputAction.done
                    : TextInputAction.next)),
        onSubmitted: (_) {
          if (maxLines > 1) return;

          if (nextFocusNode != null) {
            nextFocusNode.requestFocus();
          } else {
            onDone?.call();
          }
        },
        decoration: inputDecoration(
          label: label,
          hintText: hintText,
          suffixText: suffixText,
          icon: icon,
        ),
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
            child: Text('성별',
                style: TextStyle(color: textGrey, fontSize: 13)),
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

  Widget headerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF16305E),
            Color(0xFF22437C),
          ],
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
              const Text(
                'BALANCARE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '환자 정보 수정',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '환자 기본정보를 수정합니다.',
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

  Widget sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: mintSoft,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: mintDark, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: textGrey,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget sectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
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

  Widget infoNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: mintSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC3D5EE)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: mintDark,
            size: 20,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              '생년월일은 19980101처럼 숫자만 입력해도 됩니다. 저장 시 1998-01-01 형식으로 자동 정리됩니다.',
              style: TextStyle(
                color: mintDark,
                height: 1.35,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget saveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: mintDark,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        onPressed: isSaving ? null : savePatient,
        icon: isSaving
            ? const SizedBox(
                width: 0,
                height: 0,
              )
            : const Icon(Icons.save_rounded),
        label: isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text('수정 저장'),
      ),
    );
  }

  Widget editForm() {
    return sectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionTitle(
            icon: Icons.person_rounded,
            title: '기본 정보',
            subtitle: '환자 이름, 생년월일, 병실, 신체 정보를 입력합니다.',
          ),
          const SizedBox(height: 16),
          infoNotice(),
          const SizedBox(height: 18),
          inputField(
            controller: nameController,
            focusNode: nameFocusNode,
            nextFocusNode: birthDateFocusNode,
            label: '환자 이름',
            icon: Icons.person_outline_rounded,
          ),
          genderSelector(),
          inputField(
            controller: birthDateController,
            focusNode: birthDateFocusNode,
            nextFocusNode: roomFocusNode,
            label: '생년월일',
            hintText: '예: 19980101 또는 1998-01-01',
            keyboardType: TextInputType.datetime,
            icon: Icons.cake_outlined,
          ),
          inputField(
            controller: roomController,
            focusNode: roomFocusNode,
            nextFocusNode: heightFocusNode,
            label: '병실 / 위치',
            keyboardType: TextInputType.text,
            suffixText: '호',
            icon: Icons.meeting_room_outlined,
          ),
          Row(
            children: [
              Expanded(
                child: inputField(
                  controller: heightController,
                  focusNode: heightFocusNode,
                  nextFocusNode: weightFocusNode,
                  label: '키',
                  keyboardType: TextInputType.number,
                  suffixText: 'cm',
                  icon: Icons.height_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: inputField(
                  controller: weightController,
                  focusNode: weightFocusNode,
                  nextFocusNode: noteFocusNode,
                  label: '몸무게',
                  keyboardType: TextInputType.number,
                  suffixText: 'kg',
                  icon: Icons.monitor_weight_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          sectionTitle(
            icon: Icons.note_alt_outlined,
            title: '특이사항',
            subtitle: '환자 주의사항을 입력합니다.',
          ),
          const SizedBox(height: 16),
          inputField(
            controller: noteController,
            focusNode: noteFocusNode,
            label: '특이사항 / 주의사항',
            keyboardType: TextInputType.multiline,
            maxLines: 3,
            icon: Icons.note_alt_outlined,
          ),
          const SizedBox(height: 8),
          saveButton(),
        ],
      ),
    );
  }

  Widget loadingView() {
    return const Scaffold(
      backgroundColor: pageBg,
      body: Center(
        child: CircularProgressIndicator(
          color: mintDark,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return loadingView();
    }

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
                    headerCard(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                      child: editForm(),
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