import 'dart:async';

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
/// 쓰고, 멈춰 있을 때는 60초마다 살아있음 신호만 쓴다. 그래서 무료 한도를
/// 거의 먹지 않는다.
///
/// StatefulWidget 인 이유: 로봇이 조용히 죽으면 **새 문서가 안 온다**.
/// 스트림만 보고 있으면 마지막 값('대기 중')이 화면에 그대로 굳어서, 죽은
/// 로봇이 멀쩡해 보인다. 그래서 따로 시계를 돌려 신호가 끊긴 것을 알아챈다.
class _RobotStatusBar extends StatefulWidget {
  const _RobotStatusBar();

  @override
  State<_RobotStatusBar> createState() => _RobotStatusBarState();
}

class _RobotStatusBarState extends State<_RobotStatusBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 마감까지 남은 시간을 다시 재기만 한다. Firestore 를 읽지 않는다.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// 브릿지는 ISO 8601 문자열로, 앱은 Timestamp 로 쓴다. 둘 다 받는다.
  static DateTime? _time(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  /// 로봇이 쓰는 지도 이름을 사람이 읽는 말로.
  static String _mapLabel(String m) => switch (m) {
        'lab_4F' => '연구소 4층',
        'ward_edit' => '병동',
        '' => '알 수 없음',
        _ => m,
      };

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
        final paused = d?['paused'] == true;
        final pose = d?['pose'] as Map<String, dynamic>?;
        final map = (d?['map'] ?? '').toString();

        // 첫 응답이 오기 전에는 아직 모르는 것이지 끊긴 것이 아니다.
        // 그 짧은 사이에 빨간 '연결 끊김'이 번쩍이면 멀쩡한 로봇도 고장난
        // 것처럼 보인다.
        final unknown = !snap.hasData;

        final at = _time(d?['updatedAt']);
        final age = at == null ? null : DateTime.now().difference(at);
        final stale = RobotState.isStale(at);

        final (Color bg, Color fg, String text) = switch ((
          unknown,
          stale || !online,
          busy || paused,
        )) {
          (true, _, _) => (AppColors.pageBg, AppColors.inkDim, '로봇 상태 확인 중…'),
          (_, true, _) => (
              AppColors.dangerBg,
              AppColors.danger,
              stale
                  // 전원이 빠졌거나 네트워크가 끊긴 쪽이다. online 은 로봇이
                  // 직접 false 로 바꿔 쓴 것이라, 곱게 꺼졌다는 뜻이다.
                  ? '로봇 신호 끊김(${_ago(age ?? Duration.zero)} 전) — 배차해도 움직이지 않습니다'
                  : '로봇 연결 끊김 — 배차해도 움직이지 않습니다'
            ),
          (_, false, true) => (
              AppColors.warnBg,
              AppColors.warn,
              paused ? '로봇 멈춰 세움' : '로봇 이동 중'
            ),
          (_, false, false) => (AppColors.okBg, AppColors.ok, '로봇 대기 중'),
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
                    : (stale || !online)
                        ? Icons.cloud_off_rounded
                        : Icons.smart_toy_rounded,
                color: fg,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w800),
                ),
              ),
              if (!unknown) _place(d, pose, map, fg),
            ],
          ),
        );
      },
    );
  }

  /// 로봇이 어디 있는지.
  ///
  /// poseOnAppMap 이 false 면 좌표를 쓰지 않는다. 로봇은 좌표만 보내고 어느
  /// 지도의 좌표인지는 말하지 않는데, 지금 시험하는 연구소 지도와 병동 지도의
  /// 원점이 다르다 — 연구소 좌표를 병동 기준으로 읽으면 7m 오른쪽, 34.5m
  /// 위, 복도 밖에 로봇이 있는 것으로 나온다. 실제로 그렇게 보여서 "지도가
  /// 연결이 안 됐나" 하는 혼란이 있었다. 틀린 좌표보다 지도 이름이 낫다.
  Widget _place(
    Map<String, dynamic>? d,
    Map<String, dynamic>? pose,
    String map,
    Color fg,
  ) {
    final onAppMap = d?['poseOnAppMap'] == true;
    final String? label;
    if (!onAppMap) {
      label = map.isEmpty ? null : '시험 중 (지도: ${_mapLabel(map)})';
    } else if (pose != null) {
      label = '(${(pose['x'] as num?)?.toStringAsFixed(1) ?? '?'}, '
          '${(pose['y'] as num?)?.toStringAsFixed(1) ?? '?'})';
    } else {
      // online 인데 pose 가 없는 것은 고장이 아니다. 로봇이 아직 자기 위치를
      // 못 찾은 것뿐이라, 끊김으로 보이게 하지 않는다.
      label = '위치 확인 중';
    }
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Text(
        label,
        style: TextStyle(color: fg.withValues(alpha: 0.75)),
      ),
    );
  }

  /// '3분', '2시간' 처럼 짧게. 초 단위까지 보여 줄 일은 없다 —
  /// 2분이 지나야 뜨는 글이다.
  static String _ago(Duration d) {
    if (d.inHours >= 24) return '${d.inDays}일';
    if (d.inMinutes >= 60) return '${d.inHours}시간';
    return '${d.inMinutes}분';
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
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
            // 한 줄에 다 담는다.
            //
            // 전에는 무엇을 요청했는지가 위에 작게 있고 그 아래 '수락'이 화면
            // 폭만큼 깔려 있었다. 눈이 먼저 가는 것이 단추라, 정작 무엇을
            // 보내야 하는지가 안 보였다. 읽을 것을 왼쪽에 크게 두고 단추는
            // 필요한 만큼만 오른쪽에 붙인다.
            Row(
              children: [
                _roomBadge(r.room),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.itemsText,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _time(r.createdAt),
                            style: const TextStyle(
                              color: AppColors.inkDim,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusChip(r.status),
                          // 멈춰 세운 것은 상태와 따로 표시한다. 상태는
                          // 어디까지 갔는지를, 이것은 지금 가고 있는지를 말한다.
                          if (r.paused) ...[
                            const SizedBox(width: 6),
                            _pill('멈춤', AppColors.warnBg, AppColors.warn),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                _actions(context, r, action),
              ],
            ),
            if (r.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 62),
                child: Text(
                  '메모: ${r.note}',
                  style: const TextStyle(
                    color: AppColors.inkMid,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (failed && r.failReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 62),
                child: Text(
                  '실패 사유: ${r.failReason}',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 병실 표시. 값이 '신관 428'처럼 앞말이 붙어 오기도 해서 두 줄까지 받는다.
  Widget _roomBadge(String room) {
    final t = room.trim();
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        t.isEmpty ? '-' : t.replaceAll(' ', '\n'),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.brand,
          fontWeight: FontWeight.w900,
          fontSize: 13,
          height: 1.15,
        ),
      ),
    );
  }

  /// 오른쪽 단추 묶음. 지금 무엇을 할 수 있는지에 따라 달라진다.
  Widget _actions(
    BuildContext context,
    DeliveryRequest r,
    ({String next, String label})? action,
  ) {
    // 사람이 넘길 차례 — 다음 단계 단추와 취소.
    if (action != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            label: _busy ? '처리 중…' : action.label,
            filled: true,
            onTap: _busy ? null : () => _move(action.next),
          ),
          const SizedBox(width: 8),
          _button(
            label: '취소',
            color: AppColors.inkDim,
            onTap: _busy ? null : () => _confirmCancel(context),
          ),
        ],
      );
    }

    // 로봇이 움직이는 중 — 멈춰 세우거나 무를 수 있다.
    if (r.isMoving) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            label: r.paused ? '다시 보내기' : '잠깐 멈춤',
            color: r.paused ? AppColors.brand : AppColors.warn,
            onTap: _busy ? null : () => _setPaused(!r.paused),
          ),
          const SizedBox(width: 8),
          _button(
            label: '배송 취소',
            color: AppColors.danger,
            onTap: _busy ? null : () => _confirmCancel(context),
          ),
        ],
      );
    }

    // 복귀 중이거나 이미 끝난 것 — 사람이 할 일이 없다.
    if (!r.isActive) return const SizedBox.shrink();
    return const SizedBox(
      width: 15,
      height: 15,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Widget _button({
    required String label,
    required VoidCallback? onTap,
    bool filled = false,
    Color color = AppColors.brand,
  }) {
    final off = onTap == null;
    return SizedBox(
      height: 46,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                side: BorderSide(color: off ? AppColors.line : color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(
          text,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      );

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
