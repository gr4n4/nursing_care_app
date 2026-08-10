import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NurseProfileEditPage extends StatefulWidget {
  const NurseProfileEditPage({super.key});

  @override
  State<NurseProfileEditPage> createState() => _NurseProfileEditPageState();
}

class _NurseProfileEditPageState extends State<NurseProfileEditPage> {
  static const Color mintDark = Color(0xFF0F766E);
  static const Color mintSoft = Color(0xFFE6FAF8);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);

  final nameController = TextEditingController();
  final assignedRoomsController = TextEditingController();
  final phoneController = TextEditingController();

  final nameFocusNode = FocusNode();
  final assignedRoomsFocusNode = FocusNode();
  final phoneFocusNode = FocusNode();

  bool isLoading = true;
  bool isSaving = false;

  String email = '';
  String role = '';

  String cleanEmail() {
    final user = FirebaseAuth.instance.currentUser;
    return user?.email?.trim().toLowerCase() ?? '';
  }

  String roleText(String value) {
    if (value == 'nurse') return '간호사';
    if (value == 'admin') return '관리자';
    return value.isEmpty ? '-' : value;
  }

  Future<void> loadProfile() async {
    try {
      final currentEmail = cleanEmail();

      if (currentEmail.isEmpty) {
        throw Exception('로그인 정보를 찾을 수 없습니다.');
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentEmail)
          .get();

      if (!doc.exists) {
        throw Exception('간호사 정보를 찾을 수 없습니다.');
      }

      final data = doc.data()!;

      email = currentEmail;
      role = (data['role'] ?? '').toString();

      nameController.text = (data['name'] ?? '').toString();
      assignedRoomsController.text = (data['assignedRooms'] ?? '').toString();
      phoneController.text = (data['phone'] ?? '').toString();

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
        SnackBar(content: Text('간호사 정보 불러오기 오류: $e')),
      );
    }
  }

  Future<void> saveProfile() async {
    if (isSaving) return;

    FocusScope.of(context).unfocus();

    final name = nameController.text.trim();
    final assignedRooms = assignedRoomsController.text.trim();
    final phone = phoneController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('간호사 이름을 입력해주세요.')),
      );
      return;
    }

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 이메일 정보를 찾을 수 없습니다.')),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(email).set(
        {
          'name': name,
          'assignedRooms': assignedRooms,
          'phone': phone,
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('간호사 정보가 수정되었습니다.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('간호사 정보 수정 오류: $e')),
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
    loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    assignedRoomsController.dispose();
    phoneController.dispose();

    nameFocusNode.dispose();
    phoneFocusNode.dispose();
    assignedRoomsFocusNode.dispose();

    super.dispose();
  }

  double contentMaxWidth(double screenWidth) {
    if (kIsWeb && screenWidth >= 1000) return 1000;
    if (screenWidth >= 700) return 560;
    return screenWidth;
  }

  InputDecoration inputDecoration({
    required String label,
    String? hintText,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
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
    String? hintText,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: !isSaving,
        keyboardType: keyboardType,
        textInputAction:
            nextFocusNode == null ? TextInputAction.done : TextInputAction.next,
        onSubmitted: (_) {
          if (nextFocusNode != null) {
            nextFocusNode.requestFocus();
          } else {
            saveProfile();
          }
        },
        decoration: inputDecoration(
          label: label,
          hintText: hintText,
          icon: icon,
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
            Color(0xFF7CCFC6),
            Color(0xFF3DB8AA),
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
                'CARE NOTE',
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
            '간호사 정보 수정',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '이름, 담당 병동/병실, 연락처 정보를 수정합니다.',
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

  Widget infoRow({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGrey),
      ),
      child: Row(
        children: [
          Icon(icon, color: textGrey, size: 20),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: textGrey,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value.isEmpty ? '-' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? textDark,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget accountInfoCard() {
    return sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionTitle(
            icon: Icons.verified_user_rounded,
            title: '계정 정보',
            subtitle: '이메일과 권한은 변경할 수 없습니다.',
          ),
          const SizedBox(height: 16),
          infoRow(
            label: '이메일',
            value: email,
            icon: Icons.email_outlined,
          ),
          infoRow(
            label: '권한',
            value: roleText(role),
            icon: Icons.badge_outlined,
          ),
        ],
      ),
    );
  }

  Widget editCard() {
    return sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionTitle(
            icon: Icons.edit_rounded,
            title: '수정 가능 정보',
            subtitle: '간호사 업무 화면에 표시될 정보를 수정합니다.',
          ),
          const SizedBox(height: 18),
          inputField(
            controller: nameController,
            focusNode: nameFocusNode,
            nextFocusNode: assignedRoomsFocusNode,
            label: '간호사 이름',
            icon: Icons.person_outline_rounded,
          ),
          inputField(
            controller: assignedRoomsController,
            focusNode: assignedRoomsFocusNode,
            nextFocusNode: phoneFocusNode,
            label: '담당 병동/병실',
            hintText: '예: 재활병동 301호',
            icon: Icons.meeting_room_outlined,
          ),
          inputField(
            controller: phoneController,
            focusNode: phoneFocusNode,
            label: '연락처',
            hintText: '예: 010-1234-5678',
            keyboardType: TextInputType.phone,
            icon: Icons.phone_outlined,
          ),
          const SizedBox(height: 8),
          saveButton(),
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
        onPressed: isSaving ? null : saveProfile,
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
            final bool wide = kIsWeb && constraints.maxWidth >= 900;

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
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: accountInfoCard()),
                                const SizedBox(width: 16),
                                Expanded(child: editCard()),
                              ],
                            )
                          : Column(
                              children: [
                                accountInfoCard(),
                                const SizedBox(height: 14),
                                editCard(),
                              ],
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