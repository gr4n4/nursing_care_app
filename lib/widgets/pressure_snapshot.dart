import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 압력 경보가 난 순간의 매트리스 그림.
///
/// 압력 서버가 경보와 **같은 문서 ID** 로 pressure_snapshots 에 올려 둔
/// base64 PNG(약 3KB)를 그린다. 경보 문서에 그림을 넣지 않은 이유는
/// notification_log 를 실시간 구독하는 화면이 다섯 군데라, 목록을 열 때마다
/// 100건어치 그림이 따라오기 때문이다.
///
/// 32x64 격자를 키운 그림이라 흐리게 늘이면 칸이 뭉개진다. 어느 칸이
/// 빨간지가 정보의 전부이므로 보간을 끈다.
class PressureSnapshot extends StatefulWidget {
  /// 경보 문서 ID. 스냅샷도 같은 ID 로 올라온다.
  final String docId;

  final double width;
  final double height;

  /// 경보가 뜬 직후라면 그림이 아직 안 올라왔을 수 있다. 그때는 구독해
  /// 두고 도착하면 채운다. 지난 기록을 볼 때는 한 번만 읽으면 된다.
  final bool live;

  /// 그림 아래에 붙일 설명.
  ///
  /// 부르는 쪽에서 따로 쓰지 않고 여기에 맡긴다. 그림이 없을 때 설명만
  /// 남으면 "빨간 칸이 오래 눌린 자리입니다"만 떠서 무엇을 가리키는지
  /// 알 수 없다. 둘이 같이 나타나고 같이 사라져야 한다.
  final String? caption;

  const PressureSnapshot({
    super.key,
    required this.docId,
    required this.width,
    required this.height,
    this.live = false,
    this.caption,
  });

  @override
  State<PressureSnapshot> createState() => _PressureSnapshotState();
}

class _PressureSnapshotState extends State<PressureSnapshot> {
  /// 이미 읽은 그림. 목록을 오르내릴 때마다 다시 읽으면 읽기 할당량이
  /// 아깝고 화면도 깜빡인다. 없는 것으로 확인된 것도 null 로 기억해 둔다.
  static final Map<String, Uint8List?> _cache = {};

  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    if (!widget.live) _future = _load(widget.docId);
  }

  static Future<Uint8List?> _load(String docId) async {
    if (_cache.containsKey(docId)) return _cache[docId];
    try {
      final d = await FirebaseFirestore.instance
          .collection('pressure_snapshots')
          .doc(docId)
          .get();
      final bytes = decode((d.data()?['png'] ?? '').toString());
      _cache[docId] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('압력 스냅샷 읽기 실패: $e');
      return null;
    }
  }

  static Uint8List? decode(String b64) {
    if (b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (e) {
      debugPrint('압력 스냅샷 해독 실패: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.live) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('pressure_snapshots')
            .doc(widget.docId)
            .snapshots(),
        builder: (context, snap) =>
            _view(decode((snap.data?.data()?['png'] ?? '').toString())),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) => _view(snap.data),
    );
  }

  Widget _view(Uint8List? bytes) {
    if (bytes == null) return const SizedBox.shrink();

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(widget.width > 60 ? 10 : 8),
      child: Container(
        color: const Color(0xFF0E0E10),
        child: Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );

    final caption = widget.caption;
    if (caption == null) return image;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        image,
        const SizedBox(height: 8),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.inkDim,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// 스냅샷을 큼직하게 띄우는 창. 목록의 작은 그림으로는 어느 칸인지
/// 가늠하기 어려워, 눌러서 크게 볼 수 있어야 한다.
Future<void> showPressureSnapshot(
  BuildContext context, {
  required String docId,
  required String who,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              who,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            PressureSnapshot(
              docId: docId,
              width: 192,
              height: 384,
              caption: '빨간 칸이 오래 눌린 자리입니다',
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
