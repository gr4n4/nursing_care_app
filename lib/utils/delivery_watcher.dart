import 'dart:async';
import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../models/delivery_request.dart';

/// 새 물품 요청이 들어온 것을 대시보드에 알린다.
///
/// 안 만들면 간호사가 '로봇 배차'에 직접 들어가 봐야만 요청이 온 걸 안다.
/// 병실에서 올린 요청이 몇십 분씩 방치되면 앱으로 요청할 이유가 없어진다.
///
/// 두 가지로 알린다.
///  - 옆 메뉴 '로봇 배차'에 밀린 건수를 숫자로 붙인다(늘 보임)
///  - 새로 들어온 순간 팝업과 소리(늘 보고 있지 않아도 알아챔)
///
/// 처음에는 화면 아래 한 줄로 스쳐 가게 했는데, 잠깐 지나가는 것이라 놓치기
/// 쉬웠다. 지금은 낙상 경보처럼 창을 띄우되 그만큼 다그치지는 않는다 —
/// 소리는 한 번만 나고 '나중에'로 닫을 수 있다. 위급한 것과 급한 것은 다르다.
class DeliveryWatcher {
  DeliveryWatcher._();

  /// 아직 수락하지 않은 요청 수. 옆 메뉴 숫자에 쓴다.
  static final ValueNotifier<int> pending = ValueNotifier<int>(0);

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// 이미 본 요청. 화면을 열 때 쌓여 있던 것까지 소리내지 않으려고 쓴다.
  static final Set<String> _seen = <String>{};

  /// 첫 응답을 받았는가. 첫 응답은 '새로 온 것'이 아니라 '원래 있던 것'이다.
  static bool _primed = false;

  static web.HTMLAudioElement? _audio;

  /// 대시보드가 열려 있는 동안만 지켜본다.
  ///
  /// status 하나만 거르는 조회라 복합 색인이 필요 없고, 밀린 요청만 읽으므로
  /// 평소에는 몇 건 되지 않는다.
  static void start(GlobalKey<NavigatorState> navigatorKey) {
    if (_sub != null) return;

    _sub = FirebaseFirestore.instance
        .collection('delivery_requests')
        .where('status', isEqualTo: DeliveryStatus.requested)
        .snapshots()
        .listen(
      (snap) {
        pending.value = snap.docs.length;

        final fresh = <DeliveryRequest>[];
        for (final doc in snap.docs) {
          if (_seen.add(doc.id) && _primed) {
            fresh.add(DeliveryRequest.fromDoc(doc));
          }
        }

        // 처리된 요청은 다시 '새 것'이 될 수 있어야 한다. 취소했다가 다시
        // 올린 경우까지 조용히 넘어가면 안 된다.
        _seen.removeWhere((id) => !snap.docs.any((d) => d.id == id));

        if (!_primed) {
          _primed = true;
          return;
        }
        if (fresh.isNotEmpty) _announce(navigatorKey, fresh);
      },
      onError: (Object e) {
        // 못 지켜봐도 배차 화면에서 직접 볼 수 있다. 대시보드를 막지 않는다.
        debugPrint('물품 요청 구독 실패: $e');
      },
    );
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _seen.clear();
    _primed = false;
    pending.value = 0;
  }

  /// 팝업이 이미 떠 있는가. 요청이 잇달아 오면 창이 겹쳐 쌓인다.
  static bool _dialogOpen = false;

  static void _announce(
    GlobalKey<NavigatorState> navigatorKey,
    List<DeliveryRequest> fresh,
  ) {
    _ding();

    final context = navigatorKey.currentContext;
    if (context == null) return;

    // 이미 떠 있으면 새로 띄우지 않는다. 어차피 들어가면 다 보이고,
    // 옆 메뉴 숫자에도 이미 반영돼 있다.
    if (_dialogOpen) return;
    _dialogOpen = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RequestDialog(fresh: fresh),
    ).whenComplete(() => _dialogOpen = false);
  }

  /// '보기'를 눌렀을 때 배차 화면으로 보내는 방법.
  /// 화면 이동은 대시보드가 알고 있어서 여기서는 부르기만 한다.
  static VoidCallback? onOpenRequested;

  /// 낙상 경보음과 다른, 짧고 부드러운 소리 한 번.
  /// 같은 소리를 쓰면 간호사가 낙상인 줄 알고 뛰어간다.
  static void _ding() {
    if (!kIsWeb) return;
    try {
      // 요청이 잇달아 오면 소리가 겹쳐 지저분해진다. 앞의 것을 끊고 새로 낸다.
      _audio?.pause();

      // new HTMLAudioElement() 는 브라우저가 막는 생성자다(Illegal constructor).
      final audio = web.document.createElement('audio') as web.HTMLAudioElement
        ..src = 'assets/assets/sound/ding.wav'
        ..volume = 0.7;
      // 다 울리기 전에 수거되면 소리가 끊기는 브라우저가 있어 붙들어 둔다.
      _audio = audio;
      audio.play().toDart.catchError((Object e) {
        // 브라우저가 자동 재생을 막았을 뿐이다. 글은 그대로 뜬다.
        debugPrint('물품 요청 알림음 차단됨: $e');
        return null;
      });
    } catch (e) {
      debugPrint('물품 요청 알림음 준비 실패: $e');
    }
  }
}

/// 새 물품 요청 팝업.
///
/// 낙상 경보와 일부러 다르게 만들었다. 낙상은 빨간 화면에 소리가 계속 울리고
/// 확인 말고는 길이 없다. 물품 요청은 급하지만 위급하지는 않아서, 소리는 한 번만
/// 나고 '나중에'로 닫을 수 있다. 다만 저절로 사라지지는 않는다 — 아래에서
/// 잠깐 스쳐 지나가면 놓치기 때문이다.
class _RequestDialog extends StatelessWidget {
  final List<DeliveryRequest> fresh;

  const _RequestDialog({required this.fresh});

  static const Color brand = Color(0xFF16305E);
  static const Color brandSoft = Color(0xFFDCE7F5);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);

  /// '428호'처럼 읽히게 다듬는다.
  /// 저장된 값이 '신관 428'이기도 하고 그냥 '425'이기도 해서 양쪽을 받는다.
  static String _roomLabel(String room) {
    final t = room.trim();
    if (t.isEmpty) return '위치 미정인 곳';
    return t.endsWith('호') ? t : '$t호';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brandSoft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      color: brand,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      fresh.length > 1
                          ? '새 물품 요청 ${fresh.length}건'
                          : '새 물품 요청',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 한 번에 여러 건이 와도 무엇이 왔는지는 다 보여야 한다.
              // 다만 창이 화면을 넘지 않게 다섯 건까지만 적는다.
              for (final r in fresh.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        color: textDark,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: _roomLabel(r.room),
                          style: const TextStyle(
                            color: brand,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const TextSpan(text: '에서 '),
                        TextSpan(
                          text: r.itemsText,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const TextSpan(text: ' 물품 요청이 있습니다.'),
                      ],
                    ),
                  ),
                ),
              if (fresh.length > 5)
                Text(
                  '외 ${fresh.length - 5}건',
                  style: const TextStyle(color: textGrey, fontSize: 14),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textGrey,
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '나중에',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          DeliveryWatcher.onOpenRequested?.call();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: brand,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '배차 화면으로',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
