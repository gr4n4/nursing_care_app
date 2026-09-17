import 'dart:async';
import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../theme/app_colors.dart';
import '../widgets/pressure_snapshot.dart';
import 'notification_kind.dart';
import 'pressure_site.dart';

/// 즉시 조치가 필요한 경보(낙상·걸터앉음)를 소리와 팝업으로 알린다.
///
/// 기록 누락 알림과 다른 점:
///  - 소리가 난다. 화면을 안 보고 있어도 알아채야 한다.
///  - 확인을 누르기 전에는 사라지지 않는다. 놓치면 안 되는 알림이다.
///
/// 알림이 오는 길이 둘이라 양쪽을 모두 받는다.
///  - Firestore 구독: 앱·대시보드가 열려 있을 때 즉시 반응
///  - FCM 전경 수신: 푸시가 먼저 닿는 경우
/// 둘 다 오면 중복이므로 id 로 걸러낸다.
class AlertCenter {
  const AlertCenter._();

  /// 경보로 취급할 종류. 이 값들만 소리와 팝업을 쓴다.
  /// 목록은 NotificationKind 에 둔다 — 여기는 테스트에서 불러올 수 없다.
  static const Set<String> criticalKinds = NotificationKind.criticalKinds;

  /// 소리를 이어서 낼 종류.
  ///
  /// 낙상·걸터앉음은 확인을 누를 때까지 계속 울린다. 욕창은 한 번만 낸다 —
  /// 90분 누적으로 잡는 일이라 1분 안에 달려갈 것이 아니고, 압력 대시보드를
  /// 만든 쪽도 같은 판단을 했다(짧은 소리 한 번 + 확인해야 닫히는 카드).
  /// 다그치는 강도는 소리를 잇는 대신 15분마다 다시 뜨는 것으로 낸다.
  static const Set<String> _loopingKinds = {'fall', 'bedside'};

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static final Set<String> _shown = <String>{};
  static bool _dialogOpen = false;
  static web.HTMLAudioElement? _audio;

  /// 지금 떠 있는 팝업이 어느 경보의 것인가.
  ///
  /// 다른 기기에서 확인되었을 때 "내가 띄운 게 그거였나"를 가리는 데 쓴다.
  /// 이 값이 없으면 남이 확인해도 내 화면은 계속 울린다.
  static String? _openDocId;

  /// 떠 있는 팝업을 코드에서 닫기 위한 context.
  /// 사용자가 누르지 않아도 닫아야 하는 경우가 생겨서 들고 있는다.
  static BuildContext? _dialogContext;

  /// 확인 표시에 남길 내 이름. 나중에 알림 기록을 볼 때 이메일보다
  /// 이름이 읽힌다. 앱을 켤 때 한 번만 읽어 둔다.
  static String _myName = '';

  /// 지금 띄운 경보의 소리를 이어서 낼지. 소리가 막혔을 때 다시 켜는
  /// 버튼도 같은 값을 써야 해서 들고 있는다.
  static bool _loopSound = true;

  /// 소리가 막혔는지. 브라우저가 자동 재생을 거부하면 팝업에서 알려주고
  /// 직접 누를 수단을 준다. 조용히 실패하면 아무도 모른 채 경보를 놓친다.
  static final ValueNotifier<bool> soundBlocked = ValueNotifier<bool>(false);

  /// 아직 아무도 확인하지 않은 욕창 경보 수. 옆 메뉴에 숫자로 붙인다.
  ///
  /// 이미 받고 있는 구독에서 세므로 읽기가 늘지 않는다. 팝업은 한 번 뜨고
  /// 닫히면 그만이라, 들어가 보지 않아도 남은 것이 있는지 보이게 한다.
  static final ValueNotifier<int> pendingPressure = ValueNotifier<int>(0);

  /// 앱을 켠 시각. 이전에 쌓인 지난 경보까지 울리면 안 되므로 기준점을 잡는다.
  static late DateTime _since;

  /// 알림 설정. 꺼 둔 종류는 팝업도 띄우지 않는다.
  /// emfit_server 도 같은 값을 보고 발송을 거르지만, 발송 쪽이 아직 반영 전이거나
  /// 설정을 바꾼 직후일 수 있어 받는 쪽에서도 확인한다.
  static Map<String, dynamic> _settings = const {};
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;

  /// 지금 이 종류의 경보를 받기로 되어 있는가.
  static bool _wanted(String kind) {
    final sensor = (_settings['sensorAlerts'] as Map<String, dynamic>?) ?? const {};
    if (kind == 'fall') return sensor['fall'] != false;
    // 욕창은 종일 받는다. 90분 누적이라 밤낮을 가릴 일이 아니고, 오히려
    // 밤에 오래 같은 자세로 누워 있어 더 생기기 쉽다.
    if (kind == 'pressure') return sensor['pressure'] != false;
    if (kind != 'bedside') return true;
    if (sensor['bedside'] == false) return false;

    // 걸터앉음만 시간대 제한이 있다. 시작과 끝이 같으면 종일로 본다.
    final start = _minutes(sensor['bedsideStart']);
    final end = _minutes(sensor['bedsideEnd']);
    if (start == null || end == null || start == end) return true;

    final now = DateTime.now();
    final m = now.hour * 60 + now.minute;
    // 자정을 넘기는 구간(예: 22:00~06:00)도 다룬다.
    return start < end ? (m >= start && m < end) : (m >= start || m < end);
  }

  static int? _minutes(dynamic hhmm) {
    final parts = (hhmm ?? '').toString().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final mi = int.tryParse(parts[1]);
    if (h == null || mi == null) return null;
    return h * 60 + mi;
  }

  /// 경보 구독을 시작한다. 로그인 후 한 번만 부른다.
  static void start(GlobalKey<NavigatorState> navigatorKey) {
    if (_sub != null) return;
    _since = DateTime.now();
    _loadMyName();

    // kind 로 걸러내면서 sentAt 으로 정렬하면 복합 색인이 필요하고, 색인이 만들어지는
    // 동안 구독이 통째로 실패한다. 어차피 앱을 켠 뒤에 새로 오는 경보만 보면 되는데
    // 새 문서는 항상 맨 위에 오므로, 정렬만 걸고 종류는 받아서 거른다.
    _settingsSub = FirebaseFirestore.instance
        .collection('settings')
        .doc('notifications')
        .snapshots()
        .listen(
          (d) => _settings = d.data() ?? const {},
          onError: (Object e) => debugPrint('알림 설정 구독 오류: $e'),
        );

    _sub = FirebaseFirestore.instance
        .collection('notification_log')
        .orderBy('sentAt', descending: true)
        .limit(20)
        .snapshots()
        .listen(
      (snap) {
        var waiting = 0;
        for (final doc in snap.docs) {
          final data = doc.data();
          final kind = (data['kind'] ?? '').toString();
          if (kind == 'pressure' && data['ackedAt'] == null) waiting++;
          if (!criticalKinds.contains(kind)) continue;

          // 누군가 이미 확인한 경보는 이 기기에서 울리지 않는다. 한 사람이
          // 달려갔는데 나머지 기기가 계속 우는 것을 막으려는 것이다.
          // 마침 그 경보를 띄워 놓았다면 스스로 닫는다.
          if (data['ackedAt'] != null) {
            _shown.add(doc.id);
            _dismissIfOpen(doc.id);
            continue;
          }

          final sentAt = data['sentAt'];
          if (sentAt is! Timestamp) continue;
          // 앱을 켜기 전에 있었던 경보는 다시 울리지 않는다.
          if (sentAt.toDate().isBefore(_since)) continue;

          _raise(
            navigatorKey,
            id: doc.id,
            docId: doc.id,
            kind: kind,
            title: (data['title'] ?? '경보').toString(),
            body: (data['body'] ?? '').toString(),
          );
        }
        pendingPressure.value = waiting;
      },
      onError: (Object e) => debugPrint('경보 구독 오류: $e'),
    );
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _settingsSub?.cancel();
    _settingsSub = null;
    _openDocId = null;
    _dialogContext = null;
    _stopSound();
  }

  /// FCM 전경 수신에서 넘어오는 경로.
  static void fromPush(
    GlobalKey<NavigatorState> navigatorKey,
    Map<String, dynamic> data,
  ) {
    final kind = (data['kind'] ?? '').toString();
    if (!criticalKinds.contains(kind)) return;

    _raise(
      navigatorKey,
      // Firestore 쪽과 같은 경보를 두 번 띄우지 않도록 발송 쪽이 준 tag 를 쓴다.
      id: (data['tag'] ?? data['logId'] ?? '${data['title']}${data['body']}')
          .toString(),
      // 확인 표시를 남기려면 어느 문서인지 알아야 한다. 발송 쪽이 logId 를
      // 실어 주지 않으면 이 경로로 뜬 팝업은 확인해도 다른 기기가 모른다.
      docId: data['logId']?.toString(),
      kind: kind,
      title: (data['title'] ?? '경보').toString(),
      body: (data['body'] ?? '').toString(),
    );
  }

  static void _raise(
    GlobalKey<NavigatorState> navigatorKey, {
    required String id,
    required String kind,
    required String title,
    required String body,
    String? docId,
  }) {
    if (_shown.contains(id)) return;
    _shown.add(id);

    // 꺼 둔 종류이거나 받기로 한 시간대가 아니면 조용히 넘긴다.
    if (!_wanted(kind)) return;

    // 경보가 잇달아 와도 팝업을 겹쳐 쌓지 않는다. 확인 후 다음 것이 뜬다.
    if (_dialogOpen) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    _dialogOpen = true;
    _openDocId = docId;
    _loopSound = _loopingKinds.contains(kind);
    _startSound();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // 다른 기기에서 확인되면 사용자가 누르지 않아도 닫아야 한다.
        _dialogContext = ctx;
        return _AlertDialog(
          kind: kind,
          title: title,
          body: body,
          docId: docId,
        );
      },
    ).whenComplete(() {
      _dialogOpen = false;
      _openDocId = null;
      _dialogContext = null;
      _stopSound();
    });
  }

  /// 지금 떠 있는 팝업이 이 경보의 것이면 닫는다.
  /// 다른 경보가 떠 있거나 아무것도 없으면 아무 일도 하지 않는다.
  static void _dismissIfOpen(String docId) {
    if (_openDocId != docId) return;
    final ctx = _dialogContext;
    if (ctx == null || !ctx.mounted) return;
    Navigator.pop(ctx);
  }

  /// 확인 표시에 쓸 내 이름을 미리 읽어 둔다.
  /// 못 읽으면 이메일만 남는다 — 확인 자체를 막을 일은 아니다.
  static Future<void> _loadMyName() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || email.isEmpty) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(email).get();
      _myName = (doc.data()?['name'] ?? '').toString().trim();
    } catch (e) {
      debugPrint('확인자 이름 읽기 실패: $e');
    }
  }

  /// 확인했다고 남긴다. 이 표시를 보고 다른 기기들이 조용해진다.
  ///
  /// 실패해도 팝업은 닫는다. 눌렀는데 안 닫히면 사용자는 고장으로 여기고,
  /// 그 사이 경보음은 계속 난다. 기록이 빠지는 것보다 그쪽이 나쁘다.
  static Future<void> _ack(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notification_log')
          .doc(docId)
          .update({
        'ackedAt': FieldValue.serverTimestamp(),
        'ackedBy': FirebaseAuth.instance.currentUser?.email ?? '',
        'ackedByName': _myName,
      });
    } catch (e) {
      debugPrint('경보 확인 표시 실패: $e');
    }
  }

  // ---------- 소리 ----------

  /// 웹 푸시는 알림음을 지정할 수 없다(브라우저가 무시한다).
  /// 그래서 화면이 열려 있을 때만이라도 우리가 직접 소리를 낸다.
  static void _startSound() {
    if (!kIsWeb) return;
    try {
      // new HTMLAudioElement() 는 브라우저가 막는 생성자다(Illegal constructor).
      // createElement 로 만들어야 한다.
      final audio =
          web.document.createElement('audio') as web.HTMLAudioElement
            ..src = 'assets/assets/sound/alert.wav'
            ..loop = _loopSound
            ..volume = 1.0;
      _audio = audio;
      // 브라우저는 사용자가 한 번이라도 조작한 뒤에만 소리를 허용한다.
      // 로그인 과정에서 그 조건은 채워지지만, 막히더라도 팝업은 떠야 한다.
      soundBlocked.value = false;
      audio.play().toDart.catchError((Object e) {
        debugPrint('경보음 재생 차단됨: $e');
        soundBlocked.value = true;
        return null;
      });
    } catch (e) {
      debugPrint('경보음 준비 실패: $e');
      soundBlocked.value = true;
    }
  }

  /// 자동 재생이 막혔을 때 버튼으로 다시 시도한다.
  /// 사용자가 누른 동작이라 브라우저가 허용한다.
  static void retrySound() => _startSound();

  static void _stopSound() {
    try {
      _audio?.pause();
      _audio = null;
    } catch (_) {
      // 소리를 못 멈춰도 화면 동작은 막지 않는다.
    }
  }
}

class _AlertDialog extends StatefulWidget {
  final String kind;
  final String title;
  final String body;

  /// 확인 표시를 남길 notification_log 문서. 푸시로만 들어온 경보는
  /// 문서를 모를 수 있어 없을 수도 있다(그때는 이 기기만 조용해진다).
  final String? docId;

  const _AlertDialog({
    required this.kind,
    required this.title,
    required this.body,
    this.docId,
  });

  @override
  State<_AlertDialog> createState() => _AlertDialogState();
}

class _AlertDialogState extends State<_AlertDialog> {
  final TextEditingController _site = TextEditingController();

  bool get isPressure => widget.kind == 'pressure';

  /// 종류마다 색을 따로 적지 않는다. 늘어날 때마다 분기를 고치면
  /// 어느 화면에서는 옛 색이 남는다.
  Color get accent => NotificationKind.of(widget.kind).color;

  @override
  void dispose() {
    _site.dispose();
    super.dispose();
  }

  /// 확인을 눌렀을 때. 부위를 적었으면 같이 남긴다.
  ///
  /// 어느 것도 기다리지 않는다. 눌렀으면 바로 닫혀야 한다 — 네트워크가
  /// 느리다고 경보음이 이어지면 누른 사람은 고장으로 여긴다.
  void _confirm() {
    final id = widget.docId;
    if (id != null) {
      if (isPressure) PressureSite.save(id, _site.text);
      AlertCenter._ack(id);
    }
    Navigator.pop(context);
  }

  /// 그 순간 매트리스 그림. 빨간 칸이 기준 시간을 넘긴 자리다.
  ///
  /// 경보와 따로 올라오므로 팝업이 먼저 뜰 수 있다. live 로 구독해 두고
  /// 도착하면 채운다.
  Widget _snapshotView() {
    final id = widget.docId;
    if (id == null) return const SizedBox.shrink();

    return Column(
      children: [
        PressureSnapshot(docId: id, width: 96, height: 192, live: true),
        const SizedBox(height: 8),
        const Text(
          '빨간 칸이 오래 눌린 자리입니다',
          style: TextStyle(
            color: AppColors.inkDim,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final title = widget.title;
    final body = widget.body;
    return PopScope(
      // 확인을 누르기 전에는 닫히지 않는다. 뒤로가기로도 못 넘긴다.
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    NotificationKind.of(kind).glyph(size: 46, tint: Colors.white),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              // 욕창은 그림과 입력칸이 붙어 길어진다. 작은 폰에서 넘치면
              // 확인 버튼이 화면 밖으로 밀리므로 가운데만 스크롤시킨다.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            24, 22, 24, isPressure ? 16 : 20),
                        child: Text(
                          body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                        ),
                      ),
                      if (isPressure) ...[
                        _snapshotView(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                          child: PressureSiteField(
                            controller: _site,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // 소리가 막혔으면 알려주고 직접 켤 수단을 준다.
              ValueListenableBuilder<bool>(
                valueListenable: AlertCenter.soundBlocked,
                builder: (context, blocked, _) {
                  if (!blocked) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: OutlinedButton.icon(
                      onPressed: AlertCenter.retrySound,
                      icon: const Icon(Icons.volume_up_rounded, size: 18),
                      label: const Text('소리가 나지 않으면 눌러 주세요'),
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    onPressed: _confirm,
                    // 욕창은 부위를 함께 적으므로 무엇이 저장되는지 밝힌다.
                    // 비워 두고 눌러도 닫힌다 — 급할 때 막히면 아예 안 적는
                    // 쪽을 택하게 된다.
                    child: Text(isPressure ? '저장 후 확인' : '확인'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
