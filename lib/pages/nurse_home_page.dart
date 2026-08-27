import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/care_date.dart';
import '../widgets/notification_bell.dart';
import 'input_choice_page.dart';
import 'login_page.dart';
import 'nurse_profile_edit_page.dart';
import 'patient_profile_edit_page.dart';
import 'patient_register_page.dart';

/// 간호사 홈.
/// - 일반 모드: 환자 카드 격자(우선순위 sortOrder 순). 카드를 누르면 식사량/배설량
///   선택 화면(InputChoicePage)으로 이동한다.
/// - 관리 모드(상단 "관리"): 한 화면에서 새 환자를 추가하고, 각 환자를 정보수정/제외하고,
///   드래그로 순서를 바꾸며, 다른 간호사가 등록한 환자를 내 목록에 추가한다.
///
/// 환자 문서는 공유 풀이며, 각 환자의 `assignedNurses`(담당 간호사 이메일 배열)로
/// 간호사별 "내 환자" 목록을 구분한다. 새로 가입한 간호사는 배정된 환자가 없어 홈이 비어 있고,
/// 관리 화면의 "다른 간호사가 등록한 환자"에서 골라 추가하거나 새 환자를 등록한다.
class HomePatientItem {
  final String patientId;
  final String name;
  final String gender;
  final String birthDate;
  final String room;
  final bool isMine; // 현재 간호사에게 배정된 환자인지
  final int? sortOrder;

  // 오늘(간호일 기준) 기록 상태 — 내 환자만 loadHome에서 채운다.
  bool breakfast;
  bool lunch;
  bool dinner;
  int outputCount; // 오늘 배설 기록 건수

  HomePatientItem({
    required this.patientId,
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.room,
    required this.isMine,
    required this.sortOrder,
    this.breakfast = false,
    this.lunch = false,
    this.dinner = false,
    this.outputCount = 0,
  });

  int get age {
    if (birthDate.isEmpty) return 0;
    final birth = DateTime.tryParse(birthDate);
    if (birth == null) return 0;

    final today = DateTime.now();
    int result = today.year - birth.year;
    if (today.month < birth.month ||
        (today.month == birth.month && today.day < birth.day)) {
      result--;
    }
    return result;
  }

  String get genderShort {
    if (gender == 'male') return 'M';
    if (gender == 'female') return 'F';
    return '';
  }

  String get ageGenderText {
    final parts = <String>[];
    if (age > 0) parts.add('${age}Y');
    if (genderShort.isNotEmpty) parts.add(genderShort);
    return parts.join('/');
  }
}

class NurseHomePage extends StatefulWidget {
  const NurseHomePage({super.key});

  @override
  State<NurseHomePage> createState() => _NurseHomePageState();
}

class _NurseHomePageState extends State<NurseHomePage> {
  static const Color mintDark = Color(0xFF16305E);
  static const Color mintSoft = Color(0xFFDCE7F5);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);
  static const Color dangerColor = Color(0xFFEF4444);

  int refreshKey = 0;
  bool manageMode = false;
  bool isWorking = false;

  String cleanRoom(dynamic value) {
    return value.toString().replaceAll('호', '').trim();
  }

  int roomNumber(dynamic value) {
    final text = cleanRoom(value);
    return int.tryParse(text) ?? 999999;
  }

  double contentMaxWidth(double screenWidth) {
    if (screenWidth >= 900) return 620;
    return screenWidth;
  }

  void refreshPage() {
    if (!mounted) return;
    setState(() {
      refreshKey++;
    });
  }

  int orderOf(HomePatientItem item) => item.sortOrder ?? 100000;

  void sortPatients(List<HomePatientItem> list) {
    list.sort((a, b) {
      final ao = orderOf(a);
      final bo = orderOf(b);
      if (ao != bo) return ao.compareTo(bo);

      final aRoom = roomNumber(a.room);
      final bRoom = roomNumber(b.room);
      if (aRoom != bRoom) return aRoom.compareTo(bRoom);
      return a.name.compareTo(b.name);
    });
  }

  Future<Map<String, dynamic>> loadHome() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim().toLowerCase() ?? '';

    String nurseName = '';
    if (email.isNotEmpty) {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(email).get();
      if (userDoc.exists) {
        nurseName = (userDoc.data()?['name'] ?? '').toString().trim();
      }
    }

    final snapshot =
        await FirebaseFirestore.instance.collection('patients').get();

    final all = snapshot.docs.map((doc) {
      final data = doc.data();
      final sort = data['sortOrder'];
      final assigned = (data['assignedNurses'] as List?)
              ?.map((e) => e.toString().trim().toLowerCase())
              .toList() ??
          const <String>[];
      return HomePatientItem(
        patientId: doc.id,
        name: (data['name'] ?? '이름 없음').toString(),
        gender: (data['gender'] ?? '').toString(),
        birthDate: (data['birthDate'] ?? '').toString(),
        room: cleanRoom(data['room'] ?? ''),
        isMine: email.isNotEmpty && assigned.contains(email),
        sortOrder: sort is int ? sort : (sort is double ? sort.toInt() : null),
      );
    }).toList();

    // 내 환자(배정됨) vs 다른 간호사가 등록한 환자(풀)
    final mine = all.where((e) => e.isMine).toList();
    final others = all.where((e) => !e.isMine).toList();

    sortPatients(mine);
    sortPatients(others);

    // 내 환자만 오늘 기록 상태를 병렬로 조회한다.
    await Future.wait(mine.map((p) async {
      final flags = await loadTodayFlags(p.patientId);
      p.breakfast = (flags['breakfast'] as bool?) ?? false;
      p.lunch = (flags['lunch'] as bool?) ?? false;
      p.dinner = (flags['dinner'] as bool?) ?? false;
      p.outputCount = (flags['outputCount'] as int?) ?? 0;
    }));

    return {
      'nurseName': nurseName,
      'mine': mine,
      'others': others,
    };
  }

  Future<Map<String, dynamic>> loadTodayFlags(String patientId) async {
    final today = careDateKey(DateTime.now());
    final db = FirebaseFirestore.instance;

    final mealSnap = await db
        .collection('meal_records')
        .where('patientId', isEqualTo: patientId)
        .where('date', isEqualTo: today)
        .get();

    bool b = false, l = false, d = false;
    for (final doc in mealSnap.docs) {
      final t = (doc.data()['mealType'] ?? '').toString();
      if (t == 'breakfast') b = true;
      if (t == 'lunch') l = true;
      if (t == 'dinner') d = true;
    }

    final outSnap = await db
        .collection('output_records')
        .where('patientId', isEqualTo: patientId)
        .where('date', isEqualTo: today)
        .get();

    return {
      'breakfast': b,
      'lunch': l,
      'dinner': d,
      'outputCount': outSnap.docs.length,
    };
  }

  Future<void> openInputChoice(HomePatientItem patient) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InputChoicePage(
          patientId: patient.patientId,
          patientName: patient.name,
          room: patient.room,
        ),
      ),
    );
    refreshPage();
  }

  Future<void> openPatientRegisterPage() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PatientRegisterPage()),
    );
    if (created == true) refreshPage();
  }

  Future<void> openPatientEditPage(String patientId) async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientProfileEditPage(patientId: patientId),
      ),
    );
    if (updated == true) refreshPage();
  }

  Future<void> openNurseProfileEditPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NurseProfileEditPage()),
    );
    refreshPage();
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> persistOrder(List<HomePatientItem> ordered) async {
    final batch = FirebaseFirestore.instance.batch();
    for (var i = 0; i < ordered.length; i++) {
      final ref = FirebaseFirestore.instance
          .collection('patients')
          .doc(ordered[i].patientId);
      batch.set(ref, {'sortOrder': i}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // 환자를 내 목록에 배정/해제한다. 문서와 다른 간호사의 배정은 그대로 두고
  // assignedNurses 배열에서 내 이메일만 넣거나 뺀다.
  Future<void> setAssigned({
    required String patientId,
    required String name,
    required bool assigned,
  }) async {
    if (isWorking) return;

    final email =
        FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return;

    setState(() => isWorking = true);

    try {
      await FirebaseFirestore.instance.collection('patients').doc(patientId).set(
        {
          'assignedNurses': assigned
              ? FieldValue.arrayUnion([email])
              : FieldValue.arrayRemove([email]),
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            assigned ? '$name 환자를 내 목록에 추가했습니다.' : '$name 환자를 내 목록에서 제외했습니다.',
          ),
        ),
      );
      setState(() => refreshKey++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('환자 목록 변경 오류: $e')),
      );
    } finally {
      if (mounted) setState(() => isWorking = false);
    }
  }

  Future<void> confirmRemove(HomePatientItem patient) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('내 목록에서 제외'),
        content: Text(
          '${patient.name} 환자를 내 환자 목록에서 제외할까요?\n'
          '환자 정보와 기록은 그대로 보관되며, "다른 간호사가 등록한 환자"에서 언제든 다시 추가할 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('제외'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await setAssigned(
        patientId: patient.patientId,
        name: patient.name,
        assigned: false,
      );
    }
  }

  // ---------- 헤더 ----------

  Widget headerIconButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget headerTextButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 어절 경계에서만 줄바꿈되는 제목.
  ///
  /// 한글은 기본 줄바꿈이 음절 단위라 폭이 좁아지면 '신관4병동 간 / 호사님'처럼
  /// 낱말 한가운데가 잘린다. 어절을 각각 Text로 만들어 Wrap에 넣으면
  /// 줄바꿈이 낱말 사이에서만 일어난다.
  Widget wordWrapTitle(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);

    return Wrap(
      spacing: 8,
      runSpacing: 2,
      children: [
        for (final word in words)
          Text(
            word,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }

  Widget pageHeader(String nurseName) {
    final displayName = nurseName.isEmpty ? '간호사' : nurseName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 18, 26),
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
      child: Row(
        children: [
          // 이 화면은 두 가지로 열린다.
          //  - 로그인 직후의 첫 화면(폰)  → 돌아갈 곳이 없다
          //  - 대시보드 사이드바의 '환자 기록 입력'(웹) → 돌아갈 곳이 있다
          // 후자인데 버튼이 없으면 대시보드로 돌아갈 방법이 없어 갇힌다.
          if (Navigator.canPop(context)) ...[
            headerIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NRCAREC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                wordWrapTitle(manageMode ? '환자 관리' : '$displayName 간호사님'),
              ],
            ),
          ),
          if (manageMode)
            headerTextButton(
              label: '완료',
              icon: Icons.check_rounded,
              onTap: () => setState(() => manageMode = false),
            )
          else ...[
            headerTextButton(
              label: '관리',
              icon: Icons.manage_accounts_rounded,
              onTap: () => setState(() => manageMode = true),
            ),
            const SizedBox(width: 8),
            Stack(
              clipBehavior: Clip.none,
              children: [
                headerIconButton(
                  icon: Icons.notifications_none_rounded,
                  onTap: () => NotificationBell.open(context),
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: NotificationBell.unreadDot(
                    borderColor: mintDark,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            headerIconButton(
              icon: Icons.badge_rounded,
              onTap: openNurseProfileEditPage,
            ),
            const SizedBox(width: 8),
            headerIconButton(
              icon: Icons.logout_rounded,
              onTap: logout,
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 일반 모드 (선택) ----------

  // 오늘 식사 아침·점심·저녁 표시 점. 기록되면 민트로 켜진다.
  Widget mealDot(String label, bool on) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? mintDark : const Color(0xFFF1F5F9),
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: on ? Colors.white : textGrey,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget outputChip(int count) {
    final recorded = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: recorded ? mintSoft : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: recorded ? const Color(0xFFC3D5EE) : const Color(0xFFFECACA),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            recorded
                ? Icons.check_circle_rounded
                : Icons.remove_circle_outline_rounded,
            size: 13,
            color: recorded ? mintDark : dangerColor,
          ),
          const SizedBox(width: 4),
          Text(
            recorded ? '배설 $count회' : '배설 전',
            style: TextStyle(
              color: recorded ? mintDark : dangerColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget todayStatus(HomePatientItem patient) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '식사',
              style: TextStyle(
                color: textGrey,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 6),
            mealDot('아', patient.breakfast),
            const SizedBox(width: 4),
            mealDot('점', patient.lunch),
            const SizedBox(width: 4),
            mealDot('저', patient.dinner),
          ],
        ),
        const SizedBox(height: 8),
        outputChip(patient.outputCount),
      ],
    );
  }

  Widget patientCard(HomePatientItem patient) {
    final roomText = patient.room.isEmpty ? '병실 미지정' : '${patient.room}호';
    final ageGender = patient.ageGenderText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openInputChoice(patient),
        child: Container(
          padding: const EdgeInsets.all(16),
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
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: mintSoft,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.person_rounded, color: mintDark, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            patient.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (ageGender.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            ageGender,
                            style: const TextStyle(
                              color: textGrey,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: mintSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFC3D5EE)),
                      ),
                      child: Text(
                        roomText,
                        style: const TextStyle(
                          color: mintDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              todayStatus(patient),
            ],
          ),
        ),
      ),
    );
  }

  Widget patientGrid(List<HomePatientItem> patients) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final patient in patients) patientCard(patient)],
    );
  }

  Widget emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderGrey),
      ),
      child: Column(
        children: [
          const Icon(Icons.person_off_rounded, color: textGrey, size: 42),
          const SizedBox(height: 12),
          const Text(
            '담당 환자가 없어요',
            style: TextStyle(
              color: textDark,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '새 환자를 추가하거나, "관리"에서 다른 간호사가\n등록한 환자를 내 목록으로 가져오세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: textGrey, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: mintDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: openPatientRegisterPage,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('새 환자 추가',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 관리 모드 ----------

  Widget addPatientButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: mintDark,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: openPatientRegisterPage,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('새 환자 추가',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget manageRow(HomePatientItem patient, int index) {
    final roomText = patient.room.isEmpty ? '병실 미지정' : '${patient.room}호';
    final ageGender = patient.ageGenderText;
    final sub = [roomText, if (ageGender.isNotEmpty) ageGender].join(' · ');

    return Container(
      key: ValueKey('manage_${patient.patientId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderGrey),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.drag_indicator_rounded, color: textGrey),
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: mintSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: mintDark, size: 23),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '정보수정',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_rounded),
            color: mintDark,
            onPressed: () => openPatientEditPage(patient.patientId),
          ),
          IconButton(
            tooltip: '내 목록에서 제외',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline_rounded),
            color: dangerColor,
            onPressed: isWorking ? null : () => confirmRemove(patient),
          ),
        ],
      ),
    );
  }

  // 다른 간호사가 등록한(내게 배정 안 된) 환자 — 정보 확인 후 내 목록에 추가할 수 있다.
  Widget otherRow(HomePatientItem patient) {
    final roomText = patient.room.isEmpty ? '병실 미지정' : '${patient.room}호';
    final ageGender = patient.ageGenderText;
    final sub = [roomText, if (ageGender.isNotEmpty) ageGender].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderGrey),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: textGrey, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '정보수정',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_rounded),
            color: mintDark,
            onPressed: () => openPatientEditPage(patient.patientId),
          ),
          TextButton.icon(
            onPressed: isWorking
                ? null
                : () => setAssigned(
                      patientId: patient.patientId,
                      name: patient.name,
                      assigned: true,
                    ),
            style: TextButton.styleFrom(
              foregroundColor: mintDark,
              backgroundColor: mintSoft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('추가'),
          ),
        ],
      ),
    );
  }

  Widget manageView(List<HomePatientItem> mine, List<HomePatientItem> others) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '내 환자를 추가·수정·정렬하고, 다른 간호사가 등록한 환자를 가져올 수 있어요.',
          style: TextStyle(
            color: textGrey,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        addPatientButton(),
        const SizedBox(height: 20),
        Row(
          children: [
            const Icon(Icons.groups_rounded, color: mintDark, size: 18),
            const SizedBox(width: 6),
            Text(
              '내 환자 ${mine.length}명',
              style: const TextStyle(
                color: textDark,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '손잡이(≡)를 끌어 우선순위를 바꿀 수 있어요.',
          style: TextStyle(
            color: textGrey,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (mine.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '아직 담당 환자가 없어요. 새 환자를 추가하거나 아래에서 가져오세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textGrey, fontWeight: FontWeight.w800),
            ),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = mine.removeAt(oldIndex);
              mine.insert(newIndex, item);
              setState(() {});
              await persistOrder(mine);
            },
            children: [
              for (var i = 0; i < mine.length; i++) manageRow(mine[i], i),
            ],
          ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.group_add_rounded, color: textGrey, size: 18),
              const SizedBox(width: 6),
              Text(
                '다른 간호사가 등록한 환자 ${others.length}명',
                style: const TextStyle(
                  color: textGrey,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '"추가"를 누르면 내 환자 목록에 들어와요.',
            style: TextStyle(
              color: textGrey,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...others.map(otherRow),
        ],
      ],
    );
  }

  Widget loadingView() {
    return const Scaffold(
      backgroundColor: pageBg,
      body: Center(child: CircularProgressIndicator(color: mintDark)),
    );
  }

  Widget errorView(Object? error) {
    return Scaffold(
      backgroundColor: pageBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '간호사 화면을 불러오는 중 오류가 발생했습니다.\n$error',
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: textDark, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('home_$refreshKey'),
      future: loadHome(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return errorView(snapshot.error);
        }
        if (!snapshot.hasData) {
          return loadingView();
        }

        final data = snapshot.data!;
        final nurseName = data['nurseName'].toString();
        final mine = (data['mine'] as List).cast<HomePatientItem>();
        final others = (data['others'] as List).cast<HomePatientItem>();

        return Scaffold(
          backgroundColor: pageBg,
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxContentWidth = contentMaxWidth(constraints.maxWidth);

                return SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          pageHeader(nurseName),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
                            child: manageMode
                                ? manageView(mine, others)
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '환자를 선택해주세요',
                                        style: TextStyle(
                                          color: textDark,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        '환자를 누르면 식사량·배설량을 기록할 수 있어요.',
                                        style: TextStyle(
                                          color: textGrey,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      if (mine.isEmpty)
                                        emptyState()
                                      else
                                        patientGrid(mine),
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
      },
    );
  }
}
