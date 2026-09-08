import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/delivery_request.dart';
import '../theme/app_colors.dart';

/// 로봇 배차 (웹 · 널스스테이션).
///
/// 병실에서 앱으로 올린 요청이 여기 실시간으로 뜬다. 간호사는 순서대로
/// [수락] → [물품 실었음·출발] → [수령 확인] 세 번만 누르면 되고, 그 사이
/// 로봇이 움직이는 동안에는 버튼이 사라져 "지금은 기다리는 때"임을 보인다.
///
/// 로봇 쪽 상태(at_loading·delivered·closed)는 브릿지가 실제로 도착했을 때만
/// 쓴다. 여기서는 만들지도 않고, Firestore 규칙에서도 막혀 있다.
class DeliveryDispatchPage extends StatelessWidget {
  const DeliveryDispatchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('로봇 배차'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: Column(
        children: [
          const _RobotStatusBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // 최근 것만 가져온다.
              //
              // 처리 중인 요청은 몇 건 안 되지만 끝난 요청은 계속 쌓인다.
              // 전부 받으면 화면을 열 때마다 그 전부를 읽어, 하루 20건씩만
              // 쌓여도 반 년 뒤에는 한 번 열 때 수천 건을 읽는다. 무료 한도가
              // 읽기 횟수로 걸려 있어 그대로 두면 언젠가 막힌다.
              //
              // 한 필드만 정렬하는 것은 복합 색인이 필요 없다(자동 색인으로
              // 처리된다). 색인을 따로 만들 필요 없이 그대로 쓸 수 있다.
              stream: FirebaseFirestore.instance
                  .collection('delivery_requests')
                  .orderBy('createdAt', descending: true)
                  .limit(60)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _centerNote('목록을 불러오지 못했습니다.\n${snap.error}');
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data!.docs
                    .map(DeliveryRequest.fromDoc)
                    .toList();
                final active = all.where((r) => r.isActive).toList()
                  ..sort((a, b) => (a.createdAt ?? DateTime(2000))
                      .compareTo(b.createdAt ?? DateTime(2000)));
                final finished = all.where((r) => !r.isActive).toList()
                  ..sort((a, b) => (b.createdAt ?? DateTime(2000))
                      .compareTo(a.createdAt ?? DateTime(2000)));

                if (active.isEmpty && finished.isEmpty) {
                  return _centerNote('아직 들어온 요청이 없습니다.');
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                  children: [
                    _header('처리할 요청', active.length),
                    if (active.isEmpty)
                      _emptyBox('처리할 요청이 없습니다.')
                    else
                      for (final r in active) _RequestCard(req: r),
                    if (finished.isNotEmpty) ...[
                      const SizedBox(height: 26),
                      _header('지난 요청', finished.length),
                      for (final r in finished.take(20))
                        _RequestCard(req: r, dim: true),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Widget _centerNote(String t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            t,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkDim, fontSize: 15),
          ),
        ),
      );

  static Widget _header(String t, int n) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 2),
        child: Row(
          children: [
            Text(
              t,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$n',
                style: const TextStyle(
                  color: AppColors.brand,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );

  static Widget _emptyBox(String t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Text(
          t,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkDim),
        ),
      );
}

/// 로봇이 살아 있는지, 지금 어디쯤인지.
///
/// 브릿지가 robot_state/current 한 문서만 갱신한다. 30cm 이상 움직였을 때만
/// 쓰기 때문에 무료 한도를 거의 먹지 않는다.
class _RobotStatusBar extends StatelessWidget {
  const _RobotStatusBar();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('robot_state')
          .doc('current')
          .snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        final online = d?['online'] == true;
        final busy = d?['busy'] == true;
        final pose = d?['pose'] as Map<String, dynamic>?;

        // 첫 응답이 오기 전에는 아직 모르는 것이지 끊긴 것이 아니다.
        // 그 짧은 사이에 빨간 '연결 끊김'이 번쩍이면 멀쩡한 로봇도 고장난
        // 것처럼 보인다.
        final unknown = !snap.hasData;

        final (Color bg, Color fg, String text) = switch ((
          unknown,
          online,
          busy,
        )) {
          (true, _, _) => (AppColors.pageBg, AppColors.inkDim, '로봇 상태 확인 중…'),
          (_, false, _) => (
              AppColors.dangerBg,
              AppColors.danger,
              '로봇 연결 끊김 — 배차해도 움직이지 않습니다'
            ),
          (_, true, true) => (AppColors.warnBg, AppColors.warn, '로봇 이동 중'),
          (_, true, false) => (AppColors.okBg, AppColors.ok, '로봇 대기 중'),
        };

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: bg,
          child: Row(
            children: [
              Icon(
                unknown
                    ? Icons.hourglass_empty_rounded
                    : online
                        ? Icons.smart_toy_rounded
                        : Icons.cloud_off_rounded,
                color: fg,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                text,
                style: TextStyle(color: fg, fontWeight: FontWeight.w800),
              ),
              if (pose != null) ...[
                const SizedBox(width: 12),
                Text(
                  '(${(pose['x'] as num?)?.toStringAsFixed(1) ?? '?'}, '
                  '${(pose['y'] as num?)?.toStringAsFixed(1) ?? '?'})',
                  style: TextStyle(color: fg.withValues(alpha: 0.75)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RequestCard extends StatefulWidget {
  final DeliveryRequest req;
  final bool dim;

  const _RequestCard({required this.req, this.dim = false});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  Future<void> _move(String next) async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('delivery_requests')
          .doc(widget.req.id)
          .update({'status': next, '${next}At': FieldValue.serverTimestamp()});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('상태를 바꾸지 못했습니다: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 잠깐 멈춤 / 다시 보내기.
  ///
  /// 상태는 그대로 두고 paused 만 바꾼다. 어디까지 갔는지를 지우지 않아야
  /// 다시 보낼 때 하던 일을 이어서 할 수 있다.
  Future<void> _setPaused(bool value) async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('delivery_requests')
          .doc(widget.req.id)
          .update({
        'paused': value,
        'pausedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('로봇을 멈추지 못했습니다: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 이동 중 취소는 한 번 더 묻는다.
  /// 로봇이 이미 나가 있어서, 잘못 누르면 물품이 가지 않는다.
  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          '배송을 취소할까요?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          '${widget.req.room.isEmpty ? '' : '${widget.req.room} · '}'
          '${widget.req.itemsText}\n\n'
          '로봇이 가던 것을 멈추고 대기 자리로 돌아갑니다.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니요'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('취소합니다'),
          ),
        ],
      ),
    );
    if (ok == true) await _move(DeliveryStatus.canceled);
  }

  /// 요청 시각. 병동에서는 "언제 들어왔나"가 핵심이라 초는 생략한다.
  String _time(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) return '오늘 $hm';
    return '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.day.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.req;
    final action = DeliveryStatus.nextAction(r.status);
    final failed = r.status == DeliveryStatus.failed;

    return Opacity(
      opacity: widget.dim ? 0.62 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: failed ? AppColors.danger : AppColors.line,
            width: failed ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.brandSoft,
                  child: Text(
                    r.room.isEmpty ? '-' : r.room,
                    style: const TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.itemsText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _time(r.createdAt),
                        style: const TextStyle(
                          color: AppColors.inkDim,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(r.status),
              ],
            ),
            if (r.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '메모: ${r.note}',
                  style: const TextStyle(color: AppColors.inkMid),
                ),
              ),
            if (failed && r.failReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '실패 사유: ${r.failReason}',
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            if (action != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _busy ? null : () => _move(action.next),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _busy ? '처리 중…' : action.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _move(DeliveryStatus.canceled),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.inkDim,
                        side: const BorderSide(color: AppColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('취소'),
                    ),
                  ),
                ],
              ),
            ] else if (r.isActive) ...[
              // 로봇이 움직이는 중. 다음 단계를 넘기는 버튼은 뜻이 없지만,
              // 멈춰 세우거나 무르는 것은 이때가 오히려 필요하다
              // (환자가 자리를 비웠거나, 잘못 보냈거나, 길을 막고 있거나).
              const SizedBox(height: 14),
              Row(
                children: [
                  if (r.paused)
                    const Icon(
                      Icons.pause_circle_filled_rounded,
                      size: 18,
                      color: AppColors.warn,
                    )
                  else
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.paused ? '멈춰 세웠습니다 · 다시 보낼 수 있습니다' : _waitingText(r.status),
                      style: TextStyle(
                        color: r.paused ? AppColors.warn : AppColors.inkMid,
                        fontWeight:
                            r.paused ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              if (r.isMoving) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed:
                              _busy ? null : () => _setPaused(!r.paused),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                r.paused ? AppColors.brand : AppColors.warn,
                            side: BorderSide(
                              color:
                                  r.paused ? AppColors.brand : AppColors.warn,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Icon(
                            r.paused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 20,
                          ),
                          label: Text(
                            r.paused ? '다시 보내기' : '잠깐 멈춤',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _confirmCancel(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '배송 취소',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _waitingText(String s) => switch (s) {
        DeliveryStatus.accepted => '로봇이 널스스테이션으로 오는 중입니다',
        DeliveryStatus.delivering => '로봇이 병실로 가는 중입니다',
        DeliveryStatus.done => '로봇이 대기 자리로 돌아가는 중입니다',
        _ => '로봇이 움직이는 중입니다',
      };

  Widget _statusChip(String s) {
    final (Color bg, Color fg) = switch (s) {
      DeliveryStatus.requested => (AppColors.warnBg, AppColors.warn),
      DeliveryStatus.delivered => (AppColors.okBg, AppColors.ok),
      DeliveryStatus.closed => (AppColors.okBg, AppColors.ok),
      DeliveryStatus.failed => (AppColors.dangerBg, AppColors.danger),
      DeliveryStatus.canceled => (AppColors.pageBg, AppColors.inkDim),
      _ => (AppColors.brandSoft, AppColors.brand),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        DeliveryStatus.label(s),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    );
  }
}
