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
///  - 새로 들어온 순간 화면 아래에 한 줄과 소리(늘 보고 있지 않아도 알아챔)
///
/// 낙상 경보와 달리 화면을 막지 않는다. 물품 요청은 급하지만 위급하지는
/// 않아서, 하던 기록을 끊고 확인을 강요할 일이 아니다.
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

  static void _announce(
    GlobalKey<NavigatorState> navigatorKey,
    List<DeliveryRequest> fresh,
  ) {
    _ding();

    final context = navigatorKey.currentContext;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final first = fresh.first;
    final more = fresh.length - 1;
    final where = first.room.isEmpty ? '' : '${first.room} · ';
    final text = more > 0
        ? '$where${first.itemsText} 외 $more건 요청이 들어왔습니다.'
        : '$where${first.itemsText} 요청이 들어왔습니다.';

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        backgroundColor: const Color(0xFF16305E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Row(
          children: [
            const Icon(
              Icons.local_shipping_rounded,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: '보기',
          textColor: const Color(0xFFDCE7F5),
          onPressed: () => onOpenRequested?.call(),
        ),
      ),
    );
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
