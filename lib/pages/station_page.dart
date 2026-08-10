import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/food_table.dart';
import '../utils/care_date.dart';
import 'admin_nurse_roster_page.dart';
import 'login_page.dart';
import 'nurse_home_page.dart';
import 'nurse_profile_edit_page.dart';
import 'patient_list_page.dart';

class StationPage extends StatefulWidget {
  const StationPage({super.key});

  @override
  State<StationPage> createState() => _StationPageState();
}

class _StationPageState extends State<StationPage> {
  int refreshKey = 0;

  final ScrollController horizontalController = ScrollController();
  final ScrollController verticalController = ScrollController();
  final ScrollController tableController = ScrollController();
  final ScrollController mobileController = ScrollController();

  String get todayString => careDateDisplay(DateTime.now());

  String get firestoreDateString => careDateKey(DateTime.now());

  String get weekdayString => careWeekday(DateTime.now());

  void refreshDashboard() {
    setState(() {
      refreshKey++;
    });
  }

  // 웹 대시보드에서도 환자 숨김/복구를 전환할 수 있다. (앱 홈과 동일한 isActive 토글)
  Future<void> setPatientActive(String patientId, String name, bool active) async {
    try {
      await FirebaseFirestore.instance.collection('patients').doc(patientId).set(
        {
          'isActive': active,
          'updatedAt': Timestamp.now(),
          if (!active) 'hiddenAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(active ? '$name 환자를 표시로 전환했습니다.' : '$name 환자를 숨겼습니다.'),
        ),
      );
      refreshDashboard();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('환자 표시 상태 변경 오류: $e')),
      );
    }
  }

  // 섹션 제목 Row는 Expanded가 있어 자식이 무한 너비로 '측정'된다.
  // ElevatedButton은 무한 너비를 못 버티므로 GestureDetector+Container(Row min)로 만든다.
  Widget managePatientsButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: showManageDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F766E),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_accounts_rounded, size: 20, color: Colors.white),
            SizedBox(width: 6),
            Text(
              '환자 목록 관리',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  // 환자별 대시보드 보임/숨김을 한 곳에서 토글하는 관리 창.
  Future<void> showManageDialog() async {
    final snap =
        await FirebaseFirestore.instance.collection('patients').get();

    int roomNumber(String r) => int.tryParse(r.replaceAll('호', '').trim()) ?? 999999;

    final items = snap.docs.map((d) {
      final data = d.data();
      return <String, Object>{
        'id': d.id,
        'name': (data['name'] ?? '이름 없음').toString(),
        'room': (data['room'] ?? '').toString().replaceAll('호', '').trim(),
        'active': data['isActive'] != false,
      };
    }).toList();

    items.sort((a, b) {
      final aHidden = a['active'] == true ? 0 : 1;
      final bHidden = b['active'] == true ? 0 : 1;
      if (aHidden != bHidden) return aHidden.compareTo(bHidden);
      final ar = roomNumber(a['room'].toString());
      final br = roomNumber(b['room'].toString());
      if (ar != br) return ar.compareTo(br);
      return a['name'].toString().compareTo(b['name'].toString());
    });

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.manage_accounts_rounded, color: Color(0xFF0F766E)),
                  SizedBox(width: 8),
                  Text('환자 목록 관리'),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('등록된 환자가 없습니다.'),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 460),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final it = items[i];
                            final active = it['active'] == true;
                            final room = it['room'].toString();
                            final title = room.isEmpty
                                ? it['name'].toString()
                                : '$room호 ${it['name']}';

                            return ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              title: Text(
                                title,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                active ? '대시보드 보임' : '숨김',
                                style: TextStyle(
                                  color: active
                                      ? const Color(0xFF0F766E)
                                      : const Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: Switch(
                                value: active,
                                activeColor: const Color(0xFF0F766E),
                                onChanged: (v) async {
                                  await FirebaseFirestore.instance
                                      .collection('patients')
                                      .doc(it['id'].toString())
                                      .set(
                                    {
                                      'isActive': v,
                                      'updatedAt': Timestamp.now(),
                                      if (!v) 'hiddenAt': Timestamp.now(),
                                    },
                                    SetOptions(merge: true),
                                  );
                                  setLocal(() => it['active'] = v);
                                },
                              ),
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted) refreshDashboard();
  }

  @override
  void dispose() {
    horizontalController.dispose();
    verticalController.dispose();
    tableController.dispose();
    mobileController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> loadCurrentUserPermission() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.email == null) {
      return {
        'role': '',
        'name': '',
        'canApproveNurses': false,
      };
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.email!.toLowerCase())
        .get();

    if (!userDoc.exists) {
      return {
        'role': '',
        'name': '',
        'canApproveNurses': false,
      };
    }

    final data = userDoc.data()!;
    final role = (data['role'] ?? '').toString().trim();

    return {
      'role': role,
      'name': (data['name'] ?? '').toString().trim(),
      'canApproveNurses':
          (data['canApproveNurses'] ?? false) == true || role == 'admin',
    };
  }

  int toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  int calculateAge(dynamic birthDateValue) {
    final birthDateText = (birthDateValue ?? '').toString().trim();
    if (birthDateText.isEmpty) return 0;

    final birthDate = DateTime.tryParse(birthDateText);
    if (birthDate == null) return 0;

    final today = DateTime.now();
    int age = today.year - birthDate.year;

    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }

    return age;
  }

  Future<List<Map<String, dynamic>>> loadPatientSummaries() async {
    // orderBy('room')은 room 필드가 없는 문서를 제외하므로 전부 받아 클라이언트에서 정렬한다.
    final patientsSnapshot =
        await FirebaseFirestore.instance.collection('patients').get();

    final mealSnapshot = await FirebaseFirestore.instance
        .collection('meal_records')
        .where('date', isEqualTo: firestoreDateString)
        .get();

    final waterSnapshot = await FirebaseFirestore.instance
        .collection('water_records')
        .where('date', isEqualTo: firestoreDateString)
        .get();

    final outputSnapshot = await FirebaseFirestore.instance
        .collection('output_records')
        .where('date', isEqualTo: firestoreDateString)
        .get();

    // 부종·배변타입(간호 평가). 환자·날짜별 1문서.
    final assessmentSnapshot = await FirebaseFirestore.instance
        .collection('daily_assessments')
        .where('date', isEqualTo: firestoreDateString)
        .get();

    final Map<String, Map<String, dynamic>> assessmentByPatient = {};
    for (final doc in assessmentSnapshot.docs) {
      final data = doc.data();
      final pid = (data['patientId'] ?? '').toString();
      if (pid.isNotEmpty) assessmentByPatient[pid] = data;
    }

    final List<Map<String, dynamic>> summaries = [];

    for (final patientDoc in patientsSnapshot.docs) {
      final patientId = patientDoc.id;
      final patientData = patientDoc.data();

      final age = calculateAge(patientData['birthDate']);

      int totalFoodGram = 0;
      int totalSoupMl = 0;
      int totalWaterMl = 0;

      bool breakfastRecorded = false;
      bool lunchRecorded = false;
      bool dinnerRecorded = false;

      int urineMl = 0;
      int diaperGram = 0;
      int stoolGram = 0;
      int stoolCount = 0;
      bool hasOutputRecord = false;

      for (final mealDoc in mealSnapshot.docs) {
        final data = mealDoc.data();

        if (data['patientId'] == patientId) {
          totalFoodGram += toInt(data['totalFoodGram']);
          totalSoupMl += toInt(data['totalFluidMl']);

          final mealType = data['mealType'];

          if (mealType == 'breakfast') breakfastRecorded = true;
          if (mealType == 'lunch') lunchRecorded = true;
          if (mealType == 'dinner') dinnerRecorded = true;
        }
      }

      for (final waterDoc in waterSnapshot.docs) {
        final data = waterDoc.data();

        if (data['patientId'] == patientId) {
          totalWaterMl += toInt(data['amountMl']);
        }
      }

      for (final outputDoc in outputSnapshot.docs) {
        final data = outputDoc.data();
        if (data['patientId'] != patientId) continue;

        // 배설 기록이 존재하면 양이 0이어도 기록으로 인정한다.
        hasOutputRecord = true;

        // 기저귀는 무게(g), 그 외 배뇨는 ml — 따로 집계한다.
        final isDiaper =
            data['urineType'] == 'diaper' || (data['urineUnit'] ?? '') == 'g';
        if (isDiaper) {
          diaperGram += toInt(data['urineAmount']);
        } else {
          urineMl += toInt(data['urineAmount']);
        }

        if (data['stoolYn'] == true) {
          stoolGram += toInt(data['stoolAmount']);
          stoolCount += toInt(data['stoolCount']);
        }
      }

      final totalFluidInputMl = totalSoupMl + totalWaterMl;
      // 배설량 = 소변(ml) + 기저귀(g, 1g≈1ml). 밸런스 = 섭취수분 − 배설량.
      final fluidBalanceMl = totalFluidInputMl - urineMl - diaperGram;

      final hasMealRecord =
          breakfastRecorded || lunchRecorded || dinnerRecorded;

      String status = '정상';

      if (!hasMealRecord && !hasOutputRecord) {
        status = '미기록';
      } else if (hasMealRecord && !hasOutputRecord) {
        status = '배설 확인';
      } else if (!hasMealRecord && hasOutputRecord) {
        status = '식사 확인';
      } else if (fluidBalanceMl.abs() > ioBalanceThresholdMl) {
        status = '주의';
      }

      summaries.add({
        'patientId': patientId,
        'isActive': patientData['isActive'] != false,
        'name': patientData['name'] ?? '이름 없음',
        'age': age,
        'room': (patientData['room'] ?? '').toString().replaceAll('호', '').trim(),
        'totalFoodGram': totalFoodGram,
        'totalSoupMl': totalSoupMl,
        'totalWaterMl': totalWaterMl,
        'totalFluidInputMl': totalFluidInputMl,
        'urineMl': urineMl,
        'diaperGram': diaperGram,
        'stoolGram': stoolGram,
        'stoolCount': stoolCount,
        'fluidBalanceMl': fluidBalanceMl,
        // 미기록(식사·배설 모두 없음)만 아니면 밸런스를 표시한다.
        'balanceValid': status != '미기록',
        'edemaGrade': toInt(assessmentByPatient[patientId]?['edemaGrade']),
        'stoolType': toInt(assessmentByPatient[patientId]?['stoolType']),
        'breakfastRecorded': breakfastRecorded,
        'lunchRecorded': lunchRecorded,
        'dinnerRecorded': dinnerRecorded,
        'status': status,
      });
    }

    int roomNumber(String room) {
      final t = room.replaceAll('호', '').trim();
      return int.tryParse(t) ?? 999999;
    }

    // 표시 중인 환자 먼저(병실순), 숨김 환자는 아래로.
    summaries.sort((a, b) {
      final aHidden = a['isActive'] == true ? 0 : 1;
      final bHidden = b['isActive'] == true ? 0 : 1;
      if (aHidden != bHidden) return aHidden.compareTo(bHidden);

      final ar = roomNumber(a['room'].toString());
      final br = roomNumber(b['room'].toString());
      if (ar != br) return ar.compareTo(br);
      return a['name'].toString().compareTo(b['name'].toString());
    });

    return summaries;
  }

  Widget sideMenuButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Material(
        color: selected ? const Color(0xFF14B8A6) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : const Color(0xFF0F172A),
                  size: 27,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget sidebar({
    required BuildContext context,
    required String role,
    required bool canApproveNurses,
  }) {
    final bool isAdmin = role == 'admin';
    final bool isNurse = role == 'nurse';

    return SizedBox(
      width: 230,
      child: Container(
        color: const Color(0xFFE6FAF8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 130,
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFE6FAF8),
                    Color(0xFFC7EEE9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CARE NOTE',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '$todayString ($weekdayString)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            sideMenuButton(
              icon: Icons.monitor_rounded,
              label: '모니터링',
              selected: true,
              onTap: () {},
            ),
            if (isNurse)
              sideMenuButton(
                icon: Icons.edit_note_rounded,
                label: '환자 기록 입력',
                selected: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NurseHomePage(),
                    ),
                  );
                },
              ),
            if (isAdmin)
              sideMenuButton(
                icon: Icons.people_alt_rounded,
                label: '환자 목록',
                selected: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PatientListPage(),
                    ),
                  );
                },
              ),
            if (canApproveNurses)
              sideMenuButton(
                icon: Icons.groups_rounded,
                label: '간호사 목록',
                selected: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminNurseRosterPage(),
                    ),
                  );
                },
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.68),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.assignment_turned_in_rounded,
                      size: 54,
                      color: Color(0xFF7CCFC6),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '정확한 기록이\n환자의 회복을 돕습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF134E4A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String welcomeText({
    required String role,
    required String name,
  }) {
    if (role == 'admin') {
      return '관리자님, 환영합니다.';
    }

    if (role == 'nurse') {
      if (name.isEmpty) return '간호사님, 환영합니다.';
      return '$name 간호사님, 환영합니다.';
    }

    if (name.isEmpty) return '환영합니다.';
    return '$name님, 환영합니다.';
  }

  Widget topHeader({
    required BuildContext context,
    required String role,
    required String name,
  }) {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFE6FAF8),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              role == 'admin'
                  ? Icons.admin_panel_settings_rounded
                  : Icons.medical_services_rounded,
              color: const Color(0xFF0F766E),
              size: 34,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              welcomeText(role: role, name: name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          if (role == 'nurse') ...[
            headerIconButton(
              icon: Icons.account_circle_outlined,
              label: '정보수정',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NurseProfileEditPage(),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
          headerIconButton(
            icon: Icons.refresh_rounded,
            label: '새로고침',
            onTap: refreshDashboard,
          ),
          const SizedBox(width: 8),
          headerIconButton(
            icon: Icons.logout_rounded,
            label: '로그아웃',
            onTap: () async {
              await FirebaseAuth.instance.signOut();

              if (!context.mounted) return;

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginPage(),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget headerIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: const Color(0xFF0F172A)),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return SizedBox(
      width: width,
      height: 148,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color.withOpacity(0.20)),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget summaryCards({
    required int totalPatients,
    required int missingCount,
    required int warningCount,
    required int completedCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        int columnCount = 4;

        if (maxWidth < 700) {
          columnCount = 1;
        } else if (maxWidth < 1100) {
          columnCount = 2;
        }

        final spacing = 14.0;
        final cardWidth =
            (maxWidth - (spacing * (columnCount - 1))) / columnCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            summaryCard(
              title: '전체 환자',
              value: '$totalPatients명',
              icon: Icons.groups_rounded,
              color: const Color(0xFF14B8A6),
              width: cardWidth,
            ),
            summaryCard(
              title: '미기록',
              value: '$missingCount명',
              icon: Icons.assignment_late_rounded,
              color: const Color(0xFFEF4444),
              width: cardWidth,
            ),
            summaryCard(
              title: '확인 필요',
              value: '$warningCount명',
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFF59E0B),
              width: cardWidth,
            ),
            summaryCard(
              title: '기록 완료',
              value: '$completedCount명',
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF2563EB),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget mealMark(bool recorded) {
    return Icon(
      recorded ? Icons.check_circle_rounded : Icons.cancel_rounded,
      color: recorded ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
      size: 22,
    );
  }

  // ── 부종(Pitting Edema) / 배변타입(Bristol Stool Scale) ──
  // [값, 라벨, 설명]
  static const List<List<String>> edemaScale = [
    ['0', '없음', '함몰 없음'],
    ['1', '+1', '2mm 함몰 · 즉시 회복'],
    ['2', '+2', '4mm 함몰 · 수 초 내 회복'],
    ['3', '+3', '6mm 함몰 · 10~30초 지속'],
    ['4', '+4', '8mm 함몰 · 30초 이상 지속'],
  ];

  static const List<List<String>> stoolScale = [
    ['0', '미선택', '아직 선택 안 함'],
    ['1', 'Type 1', '딱딱한 알갱이 · 심한 변비'],
    ['2', 'Type 2', '울퉁불퉁한 소시지형 · 변비'],
    ['3', 'Type 3', '표면에 균열 있는 소시지형 · 정상'],
    ['4', 'Type 4', '매끈한 소시지형 · 정상(이상적)'],
    ['5', 'Type 5', '부드러운 덩어리 · 섬유질 부족 경향'],
    ['6', 'Type 6', '경계 불분명한 죽 형태 · 경증 설사'],
    ['7', 'Type 7', '물 같은 액체 · 설사'],
  ];

  String edemaLabel(int g) => g <= 0 ? '부종' : '부종 +$g';
  String stoolLabel(int t) => t <= 0 ? '배변타입' : 'BSS $t';

  Future<void> saveAssessment(
    String patientId, {
    int? edemaGrade,
    int? stoolType,
  }) async {
    final docId = '${patientId}_$firestoreDateString';
    final data = <String, dynamic>{
      'patientId': patientId,
      'date': firestoreDateString,
      'updatedAt': Timestamp.now(),
    };
    if (edemaGrade != null) data['edemaGrade'] = edemaGrade;
    if (stoolType != null) data['stoolType'] = stoolType;

    await FirebaseFirestore.instance
        .collection('daily_assessments')
        .doc(docId)
        .set(data, SetOptions(merge: true));

    refreshDashboard();
  }

  Future<void> showScaleDialog({
    required String title,
    required String patientName,
    required List<List<String>> scale,
    required int current,
    required Color color,
    required void Function(int value) onSelect,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('$patientName · $title'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: scale.map((row) {
                final value = int.parse(row[0]);
                final selected = value == current;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onSelect(value);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withOpacity(0.12)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              selected ? color : const Color(0xFFE5E7EB),
                          width: selected ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 84,
                            child: Text(
                              row[1],
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: selected
                                    ? color
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              row[2],
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_circle_rounded,
                                color: color, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  Widget assessmentChip({
    required String label,
    required bool isSet,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSet ? color : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSet ? color : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSet ? Colors.white : const Color(0xFF475569),
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // 수분 밸런스 = 섭취수분 − 소변량. |밸런스| > ±500ml 이면 범위 초과 알림.
  Widget balanceCell(int balanceMl, bool valid) {
    if (!valid) {
      return const Text('-');
    }

    final bool out = balanceMl.abs() > ioBalanceThresholdMl;
    final Color color =
        out ? const Color(0xFFB45309) : const Color(0xFF15803D);
    final String sign = balanceMl >= 0 ? '+' : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (out) ...[
          Icon(Icons.warning_amber_rounded, size: 17, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          '$sign$balanceMl',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  // 채운 배지에서 흰 글자가 잘 보이도록 진한(700 계열) 색을 쓴다. (KS 8.5.4 휘도 대비)
  Color statusBadgeColor(String status) {
    if (status == '정상') return const Color(0xFF15803D); // green-700
    if (status == '미기록') return const Color(0xFFB91C1C); // red-700
    return const Color(0xFFB45309); // amber-700 (확인 필요 / 주의)
  }

  // 색을 못 봐도 구분되도록 상태별 아이콘을 함께 쓴다. (KS 8.5.3 색상 단독 부호화 금지)
  IconData statusIcon(String status) {
    if (status == '정상') return Icons.check_circle_rounded;
    if (status == '미기록') return Icons.cancel_rounded;
    return Icons.warning_amber_rounded;
  }

  Widget statusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusBadgeColor(status),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), color: Colors.white, size: 16),
          const SizedBox(width: 5),
          Text(
            status,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget legend() {
    return const Wrap(
      spacing: 18,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 20),
            SizedBox(width: 6),
            Text('기록 완료'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_rounded, color: Color(0xFFF59E0B), size: 20),
            SizedBox(width: 6),
            Text('확인 필요'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 20),
            SizedBox(width: 6),
            Text('미기록'),
          ],
        ),
      ],
    );
  }

  Widget dashboardTable(List<Map<String, dynamic>> summaries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Scrollbar(
              controller: tableController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: tableController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                  ),
                  child: DataTable(
                    columnSpacing: 26,
                    horizontalMargin: 22,
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF1F5F9),
                    ),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Color(0xFF1E293B),
                    ),
                    dataTextStyle: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    headingRowHeight: 60,
                    dataRowMinHeight: 74,
                    dataRowMaxHeight: 92,
                    columns: const [
                      DataColumn(label: Text('병실')),
                      DataColumn(label: Text('환자(나이)')),
                      DataColumn(label: Text('아침')),
                      DataColumn(label: Text('점심')),
                      DataColumn(label: Text('저녁')),
                      DataColumn(label: Text('식사(g)')),
                      DataColumn(label: Text('식사수분(ml)')),
                      DataColumn(label: Text('수분(ml)')),
                      DataColumn(label: Text('총수분(ml)')),
                      DataColumn(label: Text('소변(ml)')),
                      DataColumn(label: Text('기저귀(g)')),
                      DataColumn(label: Text('대변')),
                      DataColumn(label: Text('밸런스(ml)')),
                      DataColumn(label: Text('상태')),
                      DataColumn(label: Text('특이사항')),
                    ],
                    rows: summaries.map((item) {
                      final status = item['status'] as String;
                      final age = item['age'] as int;
                      final bool active = item['isActive'] == true;
                      final patientId = item['patientId'].toString();
                      final patientName = item['name'].toString();
                      final edema = toInt(item['edemaGrade']);
                      final stool = toInt(item['stoolType']);
                      final displayName =
                          age > 0 ? '$patientName\n($age세)' : patientName;

                      return DataRow(
                        color: WidgetStateProperty.resolveWith<Color?>((states) {
                          if (!active) {
                            return const Color(0xFF94A3B8).withOpacity(0.12);
                          }
                          if (status == '미기록') {
                            return const Color(0xFFEF4444).withOpacity(0.035);
                          }
                          if (status == '주의' || status.contains('확인')) {
                            return const Color(0xFFF59E0B).withOpacity(0.035);
                          }
                          return null;
                        }),
                        cells: [
                          DataCell(Text(item['room'].toString().isEmpty
                              ? '-'
                              : '${item['room']}호')),
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    height: 1.35,
                                    color: active
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                                if (!active)
                                  const Text(
                                    '숨김',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          DataCell(mealMark(item['breakfastRecorded'])),
                          DataCell(mealMark(item['lunchRecorded'])),
                          DataCell(mealMark(item['dinnerRecorded'])),
                          DataCell(Text('${item['totalFoodGram']}')),
                          DataCell(Text('${item['totalSoupMl']}')),
                          DataCell(Text('${item['totalWaterMl']}')),
                          DataCell(Text('${item['totalFluidInputMl']}')),
                          DataCell(Text('${item['urineMl']}')),
                          DataCell(Text('${item['diaperGram']}')),
                          DataCell(
                            Text(
                              '${item['stoolCount']}회 / ${item['stoolGram']}g',
                            ),
                          ),
                          DataCell(
                            balanceCell(
                              toInt(item['fluidBalanceMl']),
                              item['balanceValid'] == true,
                            ),
                          ),
                          DataCell(statusBadge(status)),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                assessmentChip(
                                  label: edemaLabel(edema),
                                  isSet: edema > 0,
                                  color: const Color(0xFF7C3AED),
                                  onTap: () => showScaleDialog(
                                    title: '부종 (Edema)',
                                    patientName: patientName,
                                    scale: edemaScale,
                                    current: edema,
                                    color: const Color(0xFF7C3AED),
                                    onSelect: (v) =>
                                        saveAssessment(patientId, edemaGrade: v),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                assessmentChip(
                                  label: stoolLabel(stool),
                                  isSet: stool > 0,
                                  color: const Color(0xFF0F766E),
                                  onTap: () => showScaleDialog(
                                    title: '배변 타입 (BSS)',
                                    patientName: patientName,
                                    scale: stoolScale,
                                    current: stool,
                                    color: const Color(0xFF0F766E),
                                    onSelect: (v) =>
                                        saveAssessment(patientId, stoolType: v),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget infoFooter() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F9FE),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Wrap(
        spacing: 24,
        runSpacing: 18,
        children: [
          SizedBox(
            width: 360,
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, color: Color(0xFF2563EB), size: 32),
                SizedBox(width: 12),
                Expanded(child: Text('새로고침을 누르면 최신 기록이 반영됩니다.')),
              ],
            ),
          ),
          SizedBox(
            width: 420,
            child: Row(
              children: [
                Icon(
                  Icons.fact_check_rounded,
                  color: Color(0xFF2563EB),
                  size: 32,
                ),
                SizedBox(width: 12),
                Expanded(child: Text('모든 항목을 기록해야 정확한 Balance가 계산됩니다.')),
              ],
            ),
          ),
          SizedBox(
            width: 360,
            child: Row(
              children: [
                Icon(
                  Icons.water_drop_outlined,
                  color: Color(0xFF2563EB),
                  size: 32,
                ),
                SizedBox(width: 12),
                Expanded(child: Text('수분 섭취와 배설량을 함께 확인해주세요.')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget mainContent({
    required BuildContext context,
    required String role,
    required String name,
    required List<Map<String, dynamic>> summaries,
  }) {
    final totalPatients = summaries.length;
    final missingCount = summaries.where((e) => e['status'] == '미기록').length;
    final warningCount = summaries
        .where(
          (e) => e['status'] == '주의' || e['status'].toString().contains('확인'),
        )
        .length;
    final completedCount = totalPatients - missingCount - warningCount;

    return Expanded(
      child: Column(
        children: [
          topHeader(
            context: context,
            role: role,
            name: name,
          ),
          Expanded(
            child: Scrollbar(
              controller: verticalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: verticalController,
                padding: const EdgeInsets.all(34),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      summaryCards(
                        totalPatients: totalPatients,
                        missingCount: missingCount,
                        warningCount: warningCount,
                        completedCount:
                            completedCount < 0 ? 0 : completedCount,
                      ),
                      const SizedBox(height: 34),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.restaurant_rounded,
                            size: 31,
                            color: Color(0xFF475569),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              '금일 식사량/배설량',
                              style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          managePatientsButton(),
                          const SizedBox(width: 16),
                          legend(),
                        ],
                      ),
                      const SizedBox(height: 18),
                      dashboardTable(summaries),
                      const SizedBox(height: 30),
                      infoFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget mobileFallback({
    required BuildContext context,
    required String role,
    required String name,
    required bool canApproveNurses,
    required List<Map<String, dynamic>> summaries,
  }) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Care Note · $todayString'),
        actions: [
          if (canApproveNurses)
            IconButton(
              tooltip: '간호사 명단',
              icon: const Icon(Icons.groups_rounded),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminNurseRosterPage(),
                  ),
                );
              },
            ),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: refreshDashboard,
          ),
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();

              if (!context.mounted) return;

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Scrollbar(
        controller: mobileController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: mobileController,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text(
                welcomeText(role: role, name: name),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              summaryCards(
                totalPatients: summaries.length,
                missingCount:
                    summaries.where((e) => e['status'] == '미기록').length,
                warningCount: summaries
                    .where(
                      (e) =>
                          e['status'] == '주의' ||
                          e['status'].toString().contains('확인'),
                    )
                    .length,
                completedCount:
                    summaries.where((e) => e['status'] == '정상').length,
              ),
              const SizedBox(height: 18),
              dashboardTable(summaries),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: loadCurrentUserPermission(),
      builder: (context, permissionSnapshot) {
        final permission = permissionSnapshot.data ??
            {
              'role': '',
              'name': '',
              'canApproveNurses': false,
            };

        final String role = (permission['role'] ?? '').toString();
        final String name = (permission['name'] ?? '').toString();
        final bool canApproveNurses =
            (permission['canApproveNurses'] ?? false) == true;

        return FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(refreshKey),
          future: loadPatientSummaries(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Text('오류: ${snapshot.error}'),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Scaffold(
                backgroundColor: Color(0xFFF5F7FA),
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final summaries = snapshot.data!;

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return mobileFallback(
                    context: context,
                    role: role,
                    name: name,
                    canApproveNurses: canApproveNurses,
                    summaries: summaries,
                  );
                }

                final desktopWidth =
                    constraints.maxWidth < 1230 ? 1230.0 : constraints.maxWidth;

                return Scaffold(
                  backgroundColor: const Color(0xFFF8FAFC),
                  body: Scrollbar(
                    controller: horizontalController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: desktopWidth,
                        height: constraints.maxHeight,
                        child: Row(
                          children: [
                            sidebar(
                              context: context,
                              role: role,
                              canApproveNurses: canApproveNurses,
                            ),
                            mainContent(
                              context: context,
                              role: role,
                              name: name,
                              summaries: summaries,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}