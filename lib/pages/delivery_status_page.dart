import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/delivery_request.dart';
import '../theme/app_colors.dart';
import '../utils/feedback.dart';

/// 배송 현황 (모바일 · 간호사).
///
/// 로봇이 병실 앞에 대 놓으면 거기 있는 사람이 [수령 완료] 를 눌러야 로봇이
/// 대기 자리로 돌아간다. 안 누르면 로봇이 복도에 선 채로 다음 배송을 못 한다.
///
/// 널스스테이션 배차 화면에도 같은 버튼이 있지만, 물건을 받는 사람은 복도에
/// 있지 스테이션에 있지 않다. 받는 자리에서 누를 수 있어야 실제로 눌린다.
///
/// 요청자 본인만 누를 수 있게 하지 않는다. 요청한 간호사와 받는 간호사가
/// 다른 일이 흔하고, 그때 로봇이 멈춰 서 있게 된다.
class DeliveryStatusPage extends StatelessWidget {
  const DeliveryStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 진행 중인 것만. 한 필드 조회라 복합 색인이 필요 없다.
    final query = FirebaseFirestore.instance
        .collection('delivery_requests')
        .where('status', whereIn: DeliveryStatus.active.toList());

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('배송 현황'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _message(
                Icons.error_outline_rounded,
                '배송 현황을 불러오지 못했습니다',
                '${snap.error}',
                AppColors.danger,
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final reqs =
                snap.data!.docs.map(DeliveryRequest.fromDoc).toList();
            if (reqs.isEmpty) {
              return _message(
                Icons.local_shipping_outlined,
                '진행 중인 배송이 없습니다',
                '물품을 요청하면 여기에서 어디까지 왔는지 보입니다.',
                AppColors.inkDim,
              );
            }

            // 받아 갈 것이 맨 위로. 지금 사람이 움직여야 하는 건이다.
            reqs.sort((a, b) {
              final ap = a.status == DeliveryStatus.delivered ? 0 : 1;
              final bp = b.status == DeliveryStatus.delivered ? 0 : 1;
              if (ap != bp) return ap - bp;
              final at = a.createdAt, bt = b.createdAt;
              if (at == null || bt == null) return 0;
              return bt.compareTo(at);
            });

            return LayoutBuilder(
              builder: (context, c) {
                final maxWidth = c.maxWidth >= 900 ? 640.0 : c.maxWidth;
                return SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        child: Column(
                          children: [
                            // 키가 없으면 목록 순서가 바뀔 때 Flutter 가 앞
                            // 카드의 State 를 뒷 카드에 물려 준다. 그러면 누른
                            // 적 없는 카드가 '처리 중…'으로 굳는다.
                            for (final r in reqs)
                              _Card(key: ValueKey(r.id), req: r),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _message(IconData icon, String title, String body, Color tint) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: tint),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.inkMid,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatefulWidget {
  final DeliveryRequest req;

  const _Card({super.key, required this.req});

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _busy = false;

  bool get _arrived => widget.req.status == DeliveryStatus.delivered;

  /// 수령 완료. 이 값이 쓰이면 로봇이 스스로 대기 자리로 돌아간다.
  ///
  /// 규칙상 앱이 쓸 수 있는 상태는 accepted·delivering·done·canceled 뿐이다.
  /// closed 는 로봇이 복귀를 마치고 직접 쓴다.
  Future<void> _receive() async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('delivery_requests')
          .doc(widget.req.id)
          .update({
        'status': DeliveryStatus.done,
        // 기기 시각을 쓰면 폰 시계가 틀어졌을 때 구간 소요시간이 깨진다.
        'doneAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showSaveSuccess(context, message: '수령 완료로 표시했습니다.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('수령 완료를 기록하지 못했습니다: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.req;
    final (bg, fg) = _statusColors(r.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _arrived ? AppColors.ok : AppColors.line,
          width: _arrived ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.room.isEmpty ? '목적지 미상' : r.room,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  r.paused ? '잠깐 멈춤' : DeliveryStatus.label(r.status),
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r.items.map((e) => e.display).join(', '),
            style: const TextStyle(
              color: AppColors.inkMid,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
          if (r.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              r.note,
              style: const TextStyle(
                color: AppColors.inkDim,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (r.status == DeliveryStatus.failed && r.failReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              r.failReason,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (_arrived) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ok,
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
                onPressed: _busy ? null : _receive,
                child: Text(_busy ? '처리 중…' : '수령 완료'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '누르면 로봇이 대기 자리로 돌아갑니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.inkDim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              _waitingText(r.status),
              style: const TextStyle(
                color: AppColors.inkDim,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 지금 누가 무엇을 하는 중인지 한 줄로. 버튼이 없는 동안 화면이
  /// 멈춰 보이지 않게 한다.
  static String _waitingText(String s) => switch (s) {
        DeliveryStatus.requested => '널스스테이션에서 수락하기를 기다립니다.',
        DeliveryStatus.accepted => '로봇이 물품을 실으러 가는 중입니다.',
        DeliveryStatus.atLoading => '널스스테이션에서 물품을 싣는 중입니다.',
        DeliveryStatus.delivering => '로봇이 가는 중입니다.',
        DeliveryStatus.done => '로봇이 대기 자리로 돌아가는 중입니다.',
        _ => '',
      };

  static (Color, Color) _statusColors(String s) => switch (s) {
        DeliveryStatus.delivered => (AppColors.okBg, AppColors.ok),
        DeliveryStatus.requested => (AppColors.warnBg, AppColors.warn),
        DeliveryStatus.failed => (AppColors.dangerBg, AppColors.danger),
        _ => (AppColors.brandSoft, AppColors.brand),
      };
}
