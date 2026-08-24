import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/feedback.dart';
import '../utils/push_messaging.dart';

/// 기록 누락 푸시 알림의 규칙을 정하는 화면.
///
/// 값은 Firestore `settings/notifications` 한 문서에 저장하고,
/// GitHub Actions 스케줄러가 이 문서를 읽어 "언제 · 무엇을" 보낼지 판단한다.
/// 시각·임계값을 코드에 박지 않는 이유: 병동마다 라운딩 시간이 달라
/// 간호사가 직접 조정할 수 있어야 하기 때문.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  static const Color mintDark = Color(0xFF0F766E);
  static const Color mintSoft = Color(0xFFE6FAF8);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);
  static const Color dangerColor = Color(0xFFEF4444);

  static final DocumentReference<Map<String, dynamic>> settingsRef =
      FirebaseFirestore.instance.collection('settings').doc('notifications');

  bool loading = true;
  bool saving = false;

  // 전체 on/off
  bool enabled = true;

  // 식사 기록 확인 시각 (이 시각에 오늘 기록이 없으면 발송)
  TimeOfDay breakfastCheck = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay lunchCheck = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay dinnerCheck = const TimeOfDay(hour: 20, minute: 0);

  // 배설: 마지막 기록 이후 이 시간을 넘기면 발송
  int outputDayHours = 4;
  int outputNightHours = 8;
  TimeOfDay nightStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay nightEnd = const TimeOfDay(hour: 6, minute: 0);

  // 이 기기(브라우저) 등록 상태
  bool deviceRegistered = false;
  bool deviceBusy = false;

  /// 실패했을 때 실제 원인. 폰에서는 콘솔을 볼 수 없어 화면에 그대로 보여준다.
  String? deviceError;

  /// 설정 불러오기 실패 원인(있으면 저장 버튼 위에 안내를 띄운다).
  String? loadErrorText;

  /// 저장 실패 원인.
  String? saveError;

  /// 현재 브라우저 알림 권한 상태(granted/denied/notDetermined 등).
  String permissionLabel = '확인 중…';

  String get myEmail => FirebaseAuth.instance.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    load();
  }

  TimeOfDay parseTime(dynamic value, TimeOfDay fallback) {
    final text = (value ?? '').toString();
    final parts = text.split(':');
    if (parts.length != 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return fallback;
    if (h < 0 || h > 23 || m < 0 || m > 59) return fallback;
    return TimeOfDay(hour: h, minute: m);
  }

  String formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int toInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);

    // 설정 문서를 못 읽어도(규칙 거부, 느린 네트워크 등) 화면은 떠야 한다.
    // 못 읽으면 기본값으로 보여주고, 저장은 여전히 가능하다.
    DocumentSnapshot<Map<String, dynamic>>? doc;
    String? loadError;
    try {
      doc = await settingsRef.get().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      loadError = '저장된 설정을 불러오지 못했습니다(30초 초과). 아래 값은 기본값이며, '
          '이대로 저장하면 덮어씁니다. 네트워크 확인 후 "다시 불러오기"를 눌러 주세요.';
    } catch (e) {
      loadError = describeFirestoreError('설정 불러오기', e);
    }

    final registered = await PushMessaging.isRegistered();
    final permission = await PushMessaging.permissionLabel();

    if (!mounted) return;

    final data = doc?.data();
    if (data != null) {
      final meal = (data['mealChecks'] as Map<String, dynamic>?) ?? {};
      final output = (data['output'] as Map<String, dynamic>?) ?? {};

      enabled = data['enabled'] != false;
      breakfastCheck = parseTime(meal['breakfast'], breakfastCheck);
      lunchCheck = parseTime(meal['lunch'], lunchCheck);
      dinnerCheck = parseTime(meal['dinner'], dinnerCheck);
      outputDayHours = toInt(output['dayHours'], outputDayHours);
      outputNightHours = toInt(output['nightHours'], outputNightHours);
      nightStart = parseTime(output['nightStart'], nightStart);
      nightEnd = parseTime(output['nightEnd'], nightEnd);
    }

    setState(() {
      deviceRegistered = registered;
      permissionLabel = permission;
      // 기기 등록 문제와 설정 읽기 문제는 원인도 조치도 달라서 따로 표시한다.
      deviceError = PushMessaging.lastError;
      loadErrorText = loadError;
      loading = false;
    });
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      saveError = null;
    });

    // 저장도 실패하거나 멈출 수 있다. 어떤 경우에도 '저장 중…'에 갇히지 않도록
    // finally에서 반드시 풀고, 실패하면 원인을 화면에 남긴다.
    try {
      await settingsRef.set({
        'enabled': enabled,
        'mealChecks': {
          'breakfast': formatTime(breakfastCheck),
          'lunch': formatTime(lunchCheck),
          'dinner': formatTime(dinnerCheck),
        },
        'output': {
          'dayHours': outputDayHours,
          'nightHours': outputNightHours,
          'nightStart': formatTime(nightStart),
          'nightEnd': formatTime(nightEnd),
        },
        'updatedAt': Timestamp.now(),
        'updatedBy': myEmail,
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 30));

      if (!mounted) return;
      showSaveSuccess(context, message: '알림 설정이 저장되었습니다.');
    } on TimeoutException {
      if (!mounted) return;
      setState(() => saveError = '저장 30초 타임아웃 — 네트워크가 느리거나 끊겼습니다. 다시 시도해 주세요.');
    } catch (e) {
      if (!mounted) return;
      setState(() => saveError = describeFirestoreError('저장', e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// Firestore 오류를 사람이 읽을 수 있는 원인으로 바꾼다.
  /// 권한 거부와 네트워크 문제는 조치가 완전히 달라서 반드시 구분한다.
  String describeFirestoreError(String what, Object e) {
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return '$what 실패: 보안 규칙에 막혔습니다(permission-denied). 규칙에서 settings 컬렉션 접근을 확인해야 합니다.';
      }
      if (e.code == 'unavailable') {
        return '$what 실패: 서버에 연결할 수 없습니다(unavailable). 네트워크를 확인해 주세요.';
      }
      return '$what 실패: [${e.code}] ${e.message}';
    }
    return '$what 실패: $e';
  }

  Future<void> pickTime(
      TimeOfDay current, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (context, child) => MediaQuery(
        // 24시간 표기로 고정 — 병동에서 쓰는 표기와 맞춘다.
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => onPicked(picked));
  }

  Future<void> toggleThisDevice() async {
    if (myEmail.isEmpty) return;
    setState(() {
      deviceBusy = true;
      deviceError = null;
    });

    // 어떤 경로로 실패하든 버튼이 '처리 중'에 갇히지 않도록 finally에서 반드시 푼다.
    try {
      if (deviceRegistered) {
        await PushMessaging.disableOnThisDevice();
        if (!mounted) return;
        setState(() => deviceRegistered = false);
        return;
      }

      final result = await PushMessaging.enableOnThisDevice(myEmail);
      if (!mounted) return;

      setState(() {
        deviceRegistered = result == EnableResult.success;
        deviceError = PushMessaging.lastError;
      });

      switch (result) {
        case EnableResult.success:
          showSaveSuccess(context, message: '이 기기로 알림을 받습니다.');
          break;
        case EnableResult.permissionDenied:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '알림 권한이 거부되어 있어요. 브라우저 주소창의 자물쇠 아이콘 → 사이트 설정에서 알림을 허용해 주세요.',
              ),
            ),
          );
          break;
        case EnableResult.tokenFailed:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('알림 등록에 실패했어요. 아래 상세 원인을 확인해 주세요.'),
            ),
          );
          break;
      }
    } catch (e) {
      if (mounted) setState(() => deviceError = '예상치 못한 오류: $e');
    } finally {
      if (mounted) setState(() => deviceBusy = false);
    }
  }

  // ---------- 공통 UI ----------

  Widget sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderGrey),
      ),
      child: child,
    );
  }

  Widget sectionTitle(String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: mintSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: mintDark, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: textGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget timeRow(
      String label, TimeOfDay value, ValueChanged<TimeOfDay> onPicked) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => pickTime(value, onPicked),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: mintSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFC7EEE9)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, size: 17, color: mintDark),
                  const SizedBox(width: 6),
                  Text(
                    formatTime(value),
                    style: const TextStyle(
                      color: mintDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget hourRow(String label, int value, ValueChanged<int> onChanged) {
    const options = [2, 3, 4, 6, 8, 12];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: options.map((h) {
              final selected = h == value;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => onChanged(h)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? mintDark : mintSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected ? mintDark : const Color(0xFFC7EEE9),
                    ),
                  ),
                  child: Text(
                    '$h시간',
                    style: TextStyle(
                      color: selected ? Colors.white : mintDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget pageHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 18, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7CCFC6), Color(0xFF3DB8AA)],
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
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x2EFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'CARE NOTE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '알림 설정',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '기록이 빠졌을 때 언제 알릴지 정합니다.',
            style: TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget deviceCard() {
    return sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(
            '이 기기',
            deviceRegistered
                ? '이 기기에서 알림을 받는 중입니다.'
                : '알림을 받으려면 기기마다 한 번씩 허용해야 합니다.',
            deviceRegistered
                ? Icons.notifications_active_rounded
                : Icons.notifications_off_rounded,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: deviceRegistered ? Colors.white : mintDark,
                foregroundColor: deviceRegistered ? dangerColor : Colors.white,
                elevation: 0,
                side: BorderSide(
                  color: deviceRegistered ? dangerColor : mintDark,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              onPressed: deviceBusy ? null : toggleThisDevice,
              icon: Icon(
                deviceRegistered
                    ? Icons.notifications_off_rounded
                    : Icons.notifications_active_rounded,
              ),
              label: Text(
                deviceBusy
                    ? '처리 중…'
                    : deviceRegistered
                        ? '이 기기 알림 끄기'
                        : '이 기기에서 알림 받기',
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 진단 정보. 폰에서는 개발자 콘솔을 볼 수 없어 화면에 직접 보여준다.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '브라우저 알림 권한: $permissionLabel',
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (deviceError != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    deviceError!,
                    style: const TextStyle(
                      color: dangerColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget masterCard() {
    return sectionCard(
      child: Row(
        children: [
          Expanded(
            child: sectionTitle(
              '알림 사용',
              enabled ? '규칙에 따라 발송합니다.' : '모든 기록 누락 알림을 멈춥니다.',
              Icons.campaign_rounded,
            ),
          ),
          Switch(
            value: enabled,
            activeThumbColor: mintDark,
            onChanged: (v) => setState(() => enabled = v),
          ),
        ],
      ),
    );
  }

  Widget mealCard() {
    return sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(
            '식사 기록 확인 시각',
            '이 시각에 오늘 기록이 없으면 알립니다.',
            Icons.restaurant_rounded,
          ),
          const SizedBox(height: 6),
          timeRow('아침', breakfastCheck, (v) => breakfastCheck = v),
          timeRow('점심', lunchCheck, (v) => lunchCheck = v),
          timeRow('저녁', dinnerCheck, (v) => dinnerCheck = v),
          const SizedBox(height: 12),
          const Text(
            '하루 기준은 오전 7시입니다. 07:00 이전 기록은 전날로 계산됩니다.',
            style: TextStyle(
              color: textGrey,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// 설정을 못 불러왔을 때의 경고. 이 경우 화면 값은 기본값이라
  /// 그대로 저장하면 기존 설정을 덮어쓰게 되므로 반드시 알려야 한다.
  Widget loadWarningCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFB45309), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '저장된 설정을 불러오지 못했습니다',
                  style: TextStyle(
                    color: Color(0xFFB45309),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            loadErrorText!,
            style: const TextStyle(
              color: Color(0xFF92400E),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB45309),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('다시 불러오기'),
            ),
          ),
        ],
      ),
    );
  }

  Widget outputCard() {
    return sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(
            '배설 기록 간격',
            '마지막 기록 이후 이 시간을 넘기면 알립니다.',
            Icons.water_drop_rounded,
          ),
          hourRow('주간', outputDayHours, (v) => outputDayHours = v),
          hourRow('야간', outputNightHours, (v) => outputNightHours = v),
          const SizedBox(height: 6),
          timeRow('야간 시작', nightStart, (v) => nightStart = v),
          timeRow('야간 종료', nightEnd, (v) => nightEnd = v),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        bottom: false,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth >= 900
                      ? 640.0
                      : constraints.maxWidth;

                  return SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            pageHeader(),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  deviceCard(),
                                  if (loadErrorText != null) loadWarningCard(),
                                  masterCard(),
                                  mealCard(),
                                  outputCard(),
                                  if (saveError != null) ...[
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF2F2),
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFFFECACA),
                                        ),
                                      ),
                                      child: SelectableText(
                                        saveError!,
                                        style: const TextStyle(
                                          color: dangerColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: mintDark,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                        ),
                                        textStyle: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                      onPressed: saving ? null : save,
                                      icon: const Icon(Icons.save_rounded),
                                      label: Text(
                                        saving ? '저장 중…' : '알림 설정 저장',
                                      ),
                                    ),
                                  ),
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
