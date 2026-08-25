import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/food_table.dart';
import '../utils/care_date.dart';
import '../theme/app_colors.dart';
import '../widgets/notification_bell.dart';
import '../utils/feedback.dart';
import '../utils/record_export.dart';
import 'admin_nurse_roster_page.dart';
import 'login_page.dart';
import 'notification_settings_page.dart';
import 'patient_day_page.dart';
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

  /// 엑셀 내보내는 중. 파일이 커지면 몇 초 걸려서 버튼을 잠그고 표시한다.
  bool exporting = false;

  /// 내보낼 날짜를 고르고 엑셀(여러 날이면 zip)로 저장한다.
  ///
  /// 기본은 오늘 하루치. 미기록분을 나중에 채우는 일이 있어 다른 날도 고를 수 있고,
  /// 여러 날을 고르면 날짜별 파일 하나씩을 zip으로 묶는다.
  Future<void> showExportDialog() async {
    final today = DateTime.now();
    var start = today;
    var end = today;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> pick(bool isStart) async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: isStart ? start : end,
                firstDate: DateTime(2025, 1, 1),
                lastDate: today,
                helpText: isStart ? '시작 날짜' : '종료 날짜',
              );
              if (picked == null) return;
              setLocal(() {
                if (isStart) {
                  start = picked;
                  // 시작이 종료보다 뒤면 종료를 끌어올려 범위가 뒤집히지 않게 한다.
                  if (start.isAfter(end)) end = start;
                } else {
                  end = picked;
                  if (end.isBefore(start)) start = end;
                }
              });
            }

            final days = _dateRange(start, end);

            Widget dateButton(String label, DateTime value, bool isStart) {
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => pick(isStart),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          careDateDisplay(value),
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('엑셀 내보내기'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '대시보드에 보이는 환자 전체를 내보냅니다.\n'
                      '시트1 = 기록지 양식(합계), 시트2 = 상세 내역.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        dateButton('시작', start, true),
                        const SizedBox(width: 10),
                        dateButton('종료', end, false),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCE7F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        days.length == 1
                            ? '엑셀 파일 1개를 내려받습니다.'
                            : '${days.length}일치 → 파일 ${days.length}개를 zip으로 묶어 내려받습니다.',
                        style: const TextStyle(
                          color: Color(0xFF16305E),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('내려받기'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => exporting = true);
    try {
      await RecordExport.exportDates(_dateRange(start, end));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('내보내기 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  /// 시작~종료 사이의 날짜를 하루 단위로 편다.
  List<DateTime> _dateRange(DateTime start, DateTime end) {
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(end.year, end.month, end.day);
    final out = <DateTime>[];
    for (var d = a; !d.isAfter(b); d = d.add(const Duration(days: 1))) {
      out.add(d);
    }
    return out;
  }

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
  Widget exportButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: exporting ? null : showExportDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: exporting ? const Color(0xFF94A3B8) : const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              exporting ? Icons.hourglass_top_rounded : Icons.download_rounded,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              exporting ? '내보내는 중…' : '엑셀 내보내기',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget managePatientsButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: showManageDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF16305E),
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
                  Icon(Icons.manage_accounts_rounded, color: Color(0xFF16305E)),
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
                                      ? const Color(0xFF16305E)
                                      : const Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: Switch(
                                value: active,
                                activeColor: const Color(0xFF16305E),
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

      // 간호과 '섭취·배설 기록지' 양식의 칸에 맞춘 집계.
      // 튜브(관급식) / 구강(식사수분+음료+과일) / 수액(양식엔 없어 별도 칸)
      int tubeMl = 0;
      int oralMl = 0;
      int ivMl = 0;

      bool breakfastRecorded = false;
      bool lunchRecorded = false;
      bool dinnerRecorded = false;

      // 배설도 양식대로 종류별로 나눈다.
      int naturalMl = 0;
      int catheterMl = 0;
      int incontinenceMl = 0;

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

      // 식사에 포함된 수분(국·밥 등)은 입으로 들어간 것이므로 구강에 넣는다.
      oralMl += totalSoupMl;

      for (final waterDoc in waterSnapshot.docs) {
        final data = waterDoc.data();
        if (data['patientId'] != patientId) continue;

        final ml = toInt(data['amountMl']);
        totalWaterMl += ml;

        switch ((data['category'] ?? 'drink').toString()) {
          case 'tube':
            tubeMl += ml;
            break;
          case 'iv':
            ivMl += ml;
            break;
          // 음료(drink)·과일(fruit)은 모두 입으로 섭취한 것이다.
          default:
            oralMl += ml;
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
        final amount = toInt(data['urineAmount']);

        if (isDiaper) {
          diaperGram += amount;
        } else {
          urineMl += amount;
          // 기록지 양식의 자연배뇨/카테타/실금 칸을 그대로 채우기 위해 종류별로 나눈다.
          switch ((data['urineType'] ?? 'natural').toString()) {
            case 'catheter':
              catheterMl += amount;
              break;
            case 'incontinence':
              incontinenceMl += amount;
              break;
            default:
              naturalMl += amount;
          }
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
        // 기록지 양식 칸
        'tubeMl': tubeMl,
        'oralMl': oralMl,
        'ivMl': ivMl,
        'naturalMl': naturalMl,
        'catheterMl': catheterMl,
        'incontinenceMl': incontinenceMl,
        // 배설 총량 = 소변(ml) + 기저귀(g, 1g≈1ml)
        'outputTotalMl': urineMl + diaperGram,
        'urineMl': urineMl,
        'diaperGram': diaperGram,
        'stoolGram': stoolGram,
        'stoolCount': stoolCount,
        'fluidBalanceMl': fluidBalanceMl,
        // 미기록(식사·배설 모두 없음)만 아니면 밸런스를 표시한다.
        'balanceValid': status != '미기록',
        'edemaGrade': toInt(assessmentByPatient[patientId]?['edemaGrade']),
        'stoolType': toInt(assessmentByPatient[patientId]?['stoolType']),
        // 주의 해제 여부 + 사유 (간호사가 '확인함'으로 처리한 경우)
        'balanceCleared': assessmentByPatient[patientId]?['balanceCleared'] == true,
        'balanceReason':
            (assessmentByPatient[patientId]?['balanceReason'] ?? '').toString(),
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
        color: selected ? const Color(0xFF16305E) : Colors.transparent,
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
        color: const Color(0xFFDCE7F5),
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
                    Color(0xFFDCE7F5),
                    Color(0xFFC3D5EE),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BALANCARE',
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
            sideMenuButton(
              icon: Icons.notifications_active_rounded,
              label: '알림 설정',
              selected: false,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsPage(),
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
                      color: Color(0xFF16305E),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '정확한 기록이\n환자의 회복을 돕습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16305E),
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
              color: const Color(0xFFDCE7F5),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              role == 'admin'
                  ? Icons.admin_panel_settings_rounded
                  : Icons.medical_services_rounded,
              color: const Color(0xFF16305E),
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
          const NotificationBell(),
          const SizedBox(width: 8),
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
              color: const Color(0xFF16305E),
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

  /// 표 위에 놓는 요약 띠.
  ///
  /// 관제 화면의 첫 임무는 "지금 몇 명을 봐야 하나"에 답하는 것이다.
  /// 이게 없으면 17개 열짜리 표를 끝까지 훑어야 그 답이 나온다.
  Widget summaryStrip(List<Map<String, dynamic>> summaries) {
    // 숨긴 환자는 대시보드 아래로 빠지므로 집계에서도 뺀다.
    final rows = summaries.where((s) => s['isActive'] == true).toList();

    var missing = 0, caution = 0, normal = 0;
    var intakeSum = 0, outputSum = 0;

    for (final s in rows) {
      final status = (s['status'] ?? '').toString();
      if (status == '미기록') {
        missing++;
      } else if (status == '주의' && s['balanceCleared'] != true) {
        caution++;
      } else {
        normal++;
      }
      intakeSum += toInt(s['totalFluidInputMl']);
      outputSum += toInt(s['outputTotalMl']);
    }

    final n = rows.isEmpty ? 1 : rows.length;

    Widget tile({
      required String label,
      required String value,
      required String sub,
      Color? valueColor,
    }) {
      return Expanded(
        child: Container(
          // IntrinsicHeight의 예측 높이와 실제 글자 높이가 1~2px 어긋나 넘침이 났다.
          // 고정 높이를 주면 측정이 개입하지 않아 확실하다.
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          alignment: Alignment.centerLeft,
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.inkDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? AppColors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
              Text(
                sub,
                style: const TextStyle(
                  color: AppColors.inkDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.line,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      // 칸 사이 1px 간격이 배경색(line)으로 비쳐 구분선이 된다.
      // 칸마다 높이가 고정이라 stretch나 IntrinsicHeight가 필요 없다.
      child: Row(
        children: [
          tile(
            label: '미기록',
            value: '$missing',
            sub: '식사·배설 모두 없음',
            valueColor: missing > 0 ? AppColors.danger : AppColors.inkDim,
          ),
          const SizedBox(width: 1),
          tile(
            label: '밸런스 주의',
            value: '$caution',
            sub: '±$ioBalanceThresholdMl ml 초과',
            valueColor: caution > 0 ? AppColors.warn : AppColors.inkDim,
          ),
          const SizedBox(width: 1),
          tile(
            label: '정상',
            value: '$normal',
            sub: '전체 ${rows.length}명',
            valueColor: AppColors.ok,
          ),
          const SizedBox(width: 1),
          tile(
            label: '평균 섭취',
            value: '${(intakeSum / n).round()}',
            sub: 'ml / 명',
          ),
          const SizedBox(width: 1),
          tile(
            label: '평균 배설',
            value: '${(outputSum / n).round()}',
            sub: 'ml / 명',
          ),
        ],
      ),
    );
  }

  /// 병실 + 환자명을 한 칸에. 두 칸으로 나눠도 이동 경로가 같아 나눌 이유가 없다.
  Widget patientCell({
    required String room,
    required String displayName,
    required bool active,
  }) {
    final roomText = room.trim().isEmpty ? '-' : '${room.trim()}호';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFDCE7F5) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? const Color(0xFFC3D5EE) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            roomText,
            style: TextStyle(
              color: active
                  ? const Color(0xFF16305E)
                  : const Color(0xFF94A3B8),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              height: 1.35,
              color: active
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ),
        if (!active) ...[
          const SizedBox(width: 8),
          const Text(
            '숨김',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }

  /// 섭취 / 배설 / 판정 덩어리를 눈으로 가르는 세로선.
  /// 기록지 양식이 굵은 선으로 섭취량·배설량을 나눠 놓은 것을 그대로 옮겼다.
  /// DataTable은 헤더 병합을 지원하지 않아 얇은 열을 끼워 넣는 방식으로 흉내낸다.
  Widget groupDividerHead() {
    return Container(width: 2, height: 40, color: const Color(0xFF64748B));
  }

  Widget groupDividerCell() {
    return Container(width: 2, height: 60, color: const Color(0xFF94A3B8));
  }

  /// 기록지 양식 칸의 숫자.
  /// 0은 흐리게 '-'로 보여준다. 0이 잔뜩 찍혀 있으면 실제로 기록된 값이 묻혀서
  /// 메디로에 옮겨 적을 때 눈으로 훑기가 어렵다.
  Widget amountCell(int value) {
    if (value <= 0) {
      return const Text(
        '-',
        style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w700),
      );
    }
    // 원자료는 옮겨 적을 값이지 판단할 값이 아니다. 총량·밸런스보다 작고 흐리게
    // 두어야 눈이 판단값을 먼저 잡는다.
    return Text(
      '$value',
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.inkMid,
      ),
    );
  }

  /// 총량 칸. 옮겨 적을 때 기준이 되는 값이라 진하게 강조한다.
  Widget totalCell(int value) {
    return Text(
      value <= 0 ? '-' : '$value',
      style: TextStyle(
        color: value <= 0 ? const Color(0xFFCBD5E1) : AppColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
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

    if (!mounted) return;
    showSaveSuccess(context);
    refreshDashboard();
  }

  // #13 밸런스 '주의' 해제 — 사유를 남기고 상태를 '확인됨'으로.
  // 경고를 지우는 게 아니라 '간호사가 확인했고 사유는 이것'으로 기록한다(노티 누락 방지).
  Future<void> saveBalanceClear(
    String patientId, {
    required bool cleared,
    String reason = '',
  }) async {
    final docId = '${patientId}_$firestoreDateString';
    await FirebaseFirestore.instance
        .collection('daily_assessments')
        .doc(docId)
        .set(
      {
        'patientId': patientId,
        'date': firestoreDateString,
        'balanceCleared': cleared,
        'balanceReason': cleared ? reason : '',
        'balanceClearedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      },
      SetOptions(merge: true),
    );

    if (!mounted) return;
    showSaveSuccess(context);
    refreshDashboard();
  }

  Future<void> showBalanceClearDialog({
    required String patientId,
    required String name,
    required String status,
    required bool cleared,
    required String reason,
  }) async {
    // 이미 해제됨 → 사유 보기 + 되돌리기
    if (cleared) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('$name · 주의 해제됨'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '이 환자는 주의가 해제된 상태입니다.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  reason.isEmpty ? '사유 없음' : reason,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB45309),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await saveBalanceClear(patientId, cleared: false);
              },
              child: const Text('주의 다시 표시'),
            ),
          ],
        ),
      );
      return;
    }

    // 미해제 → 사유 입력 후 해제(확인 한 번 더)
    final controller = TextEditingController(text: reason);
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('$name · 주의 해제'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '주의가 뜬 이유를 확인하고 사유를 남기면 상태를 "확인됨"으로 바꿉니다.\n(경고를 숨기는 게 아니라 확인 사실을 기록합니다.)',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: '예) 땀을 많이 흘림 / 설사 / 구토 / 수액 추가',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final text = controller.text.trim();
                final ok = await showDialog<bool>(
                  context: ctx,
                  builder: (c2) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    title: const Text('주의 해제'),
                    content: const Text('정말 이 환자의 주의를 해제할까요?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c2, false),
                        child: const Text('아니오'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF15803D),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(c2, true),
                        child: const Text('해제'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await saveBalanceClear(patientId, cleared: true, reason: text);
              },
              child: const Text('주의 해제'),
            ),
          ],
        );
      },
    );
    controller.dispose();
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

  // 특이사항 칸의 '상세' 버튼 — 부종/배변타입 토글과 구분되도록 채운(파란) 버튼.
  Widget detailButton({required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1D4ED8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded, size: 15, color: Colors.white),
            SizedBox(width: 5),
            Text(
              '상세',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
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
        // 이 표에서 유일하게 '판단'에 쓰는 숫자라 가장 크게 둔다.
        Text(
          '$sign$balanceMl',
          style: TextStyle(
            color: color,
            fontSize: 18,
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

  Widget statusBadge(String status, {bool cleared = false, VoidCallback? onTap}) {
    final String label = cleared ? '확인됨' : status;
    final Color color =
        cleared ? const Color(0xFF15803D) : statusBadgeColor(status);
    final IconData icon = cleared ? Icons.verified_rounded : statusIcon(status);

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          // 누를 수 있는 배지엔 아래 화살표로 힌트를 준다.
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded,
                color: Colors.white, size: 15),
          ],
        ],
      ),
    );

    if (onTap == null) return badge;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: badge,
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








  /// 환자 클릭 → 환자별 하루 기록 페이지.
  /// 다이얼로그로는 담기 어려운 양이라 정식 화면으로 뺐다.
  /// 돌아오면 부종·주의해제 등이 바뀌었을 수 있어 목록을 다시 읽는다.
  Future<void> openPatientDayPage({
    required String patientId,
    required String name,
    required String room,
    required int age,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientDayPage(
          patientId: patientId,
          name: name,
          room: room,
          age: age,
        ),
      ),
    );
    if (mounted) refreshDashboard();
  }



  /// 열이 눌리지 않고 다 들어가는 최소 폭(구분선 2개 + 특이사항 포함 17열).
  /// 이보다 창이 좁으면 열을 줄이는 대신 가로 스크롤로 넘긴다.
  static const double dashboardTableMinWidth = 1820;

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
                // 표에 '유한한' 폭을 준다. 가로 스크롤 안에서는 폭이 무한대라
                // DataTable이 열 너비를 제대로 배분하지 못해 셀 내용이 넘친다(빗금).
                // 창이 좁으면 눌러 담는 대신 가로 스크롤이 생기도록 최소 폭을 보장한다.
                child: SizedBox(
                  width: math.max(constraints.maxWidth, dashboardTableMinWidth),
                  child: DataTable(
                    columnSpacing: 18,
                    horizontalMargin: 22,
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF1F5F9),
                    ),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.inkMid,
                    ),
                    dataTextStyle: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    headingRowHeight: 60,
                    dataRowMinHeight: 74,
                    dataRowMaxHeight: 110,
                    // 간호과 '섭취·배설 기록지' 양식의 칸 순서를 그대로 따른다.
                    // 메디로에 옮겨 적을 때 눈이 왔다갔다 하지 않게 하기 위함.
                    // (수액은 양식에 없는 칸이라 섭취 끝에 따로 둔다.)
                    columns: [
                      const DataColumn(label: Text('병실 · 환자')),
                      // ── 섭취량 ──
                      const DataColumn(label: Text('튜브')),
                      const DataColumn(label: Text('구강')),
                      const DataColumn(label: Text('수액')),
                      const DataColumn(label: Text('섭취 총량')),
                      // 양식처럼 섭취/배설 덩어리를 눈으로 갈라 준다.
                      DataColumn(label: groupDividerHead()),
                      // ── 배설량 ──
                      const DataColumn(label: Text('자연배뇨')),
                      const DataColumn(label: Text('카테타')),
                      const DataColumn(label: Text('실금')),
                      const DataColumn(label: Text('기저귀(g)')),
                      const DataColumn(label: Text('배설 총량')),
                      const DataColumn(label: Text('배변')),
                      DataColumn(label: groupDividerHead()),
                      // ── 판정 ──
                      const DataColumn(label: Text('밸런스(ml)')),
                      const DataColumn(label: Text('상태')),
                      const DataColumn(label: Text('특이사항')),
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
                          // 병실과 이름은 어차피 같은 곳으로 이동하므로 한 칸으로 합친다.
                          DataCell(
                            patientCell(
                              room: item['room'].toString(),
                              displayName: displayName,
                              active: active,
                            ),
                            onTap: () => openPatientDayPage(
                              patientId: patientId,
                              name: patientName,
                              room: item['room'].toString(),
                              age: age,
                            ),
                          ),
                          // ── 섭취량 (기록지 양식 순서) ──
                          DataCell(amountCell(toInt(item['tubeMl']))),
                          DataCell(amountCell(toInt(item['oralMl']))),
                          DataCell(amountCell(toInt(item['ivMl']))),
                          DataCell(totalCell(toInt(item['totalFluidInputMl']))),
                          DataCell(groupDividerCell()),
                          // ── 배설량 ──
                          DataCell(amountCell(toInt(item['naturalMl']))),
                          DataCell(amountCell(toInt(item['catheterMl']))),
                          DataCell(amountCell(toInt(item['incontinenceMl']))),
                          DataCell(amountCell(toInt(item['diaperGram']))),
                          DataCell(totalCell(toInt(item['outputTotalMl']))),
                          DataCell(
                            Text(
                              '${item['stoolCount']}회 / ${item['stoolGram']}g',
                            ),
                          ),
                          DataCell(groupDividerCell()),
                          DataCell(
                            balanceCell(
                              toInt(item['fluidBalanceMl']),
                              item['balanceValid'] == true,
                            ),
                          ),
                          DataCell(statusBadge(
                            status,
                            cleared: item['balanceCleared'] == true,
                            onTap: (status == '주의' ||
                                    status.contains('확인') ||
                                    item['balanceCleared'] == true)
                                ? () => showBalanceClearDialog(
                                      patientId: patientId,
                                      name: patientName,
                                      status: status,
                                      cleared: item['balanceCleared'] == true,
                                      reason: item['balanceReason'].toString(),
                                    )
                                : null,
                          )),
                          // 부종·배변타입 입력은 첫 화면에 둔다. 라운딩 중 바로
                          // 찍어야 하는 값이라 상세로 들어가게 하면 손이 많이 간다.
                          DataCell(
                            // 칩 라벨 길이가 상태에 따라 바뀌므로(부종 / 부종 +4,
                            // 배변타입 / BSS 7) Row로 두면 좁을 때 넘친다.
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
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
                                assessmentChip(
                                  label: stoolLabel(stool),
                                  isSet: stool > 0,
                                  color: AppColors.stool,
                                  onTap: () => showScaleDialog(
                                    title: '배변 타입 (BSS)',
                                    patientName: patientName,
                                    scale: stoolScale,
                                    current: stool,
                                    color: AppColors.stool,
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
    // 주의(±초과)·확인필요라도 간호사가 '주의 해제'한 환자는 경고 집계에서 뺀다.
    final warningCount = summaries
        .where(
          (e) =>
              (e['status'] == '주의' ||
                  e['status'].toString().contains('확인')) &&
              e['balanceCleared'] != true,
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
                          exportButton(),
                          const SizedBox(width: 10),
                          managePatientsButton(),
                          const SizedBox(width: 16),
                          legend(),
                        ],
                      ),
                      const SizedBox(height: 18),
                      summaryStrip(summaries),
                      const SizedBox(height: 14),
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
        title: Text('Balancare · $todayString'),
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
                          (e['status'] == '주의' ||
                              e['status'].toString().contains('확인')) &&
                          e['balanceCleared'] != true,
                    )
                    .length,
                completedCount: summaries
                    .where((e) =>
                        e['status'] == '정상' || e['balanceCleared'] == true)
                    .length,
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