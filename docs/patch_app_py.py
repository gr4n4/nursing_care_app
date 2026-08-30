"""app.py 에 NRCarec 경보 발송을 끼워 넣는다.

5,700줄짜리 파일을 손으로 고치면 어디를 건드렸는지 놓치기 쉬워서 스크립트로 넣는다.
 - 고치기 전 백업을 남긴다
 - 이미 들어가 있으면 아무것도 하지 않는다(두 번 실행해도 안전)
 - 끝나고 문법 검사를 해서, 깨졌으면 백업으로 되돌린다

젯슨에서:
    cd /home/carerobot/emfit_server
    python3 patch_app_py.py
"""

import ast
import datetime
import io
import os
import shutil
import sys

APP = 'app.py'

IMPORT_LINE = 'from nrcarec_alert import send_alert, should_send\n'
IMPORT_ANCHOR = 'import analyzer\n'

# 로그를 쓴 직후, 응답을 돌려주기 직전에 넣는다.
CALL_ANCHOR = '''    return {
        "status": "success",
        "source": "ai_radar",
        "model": record["radar_model"],
    }
'''

CALL_BLOCK = '''    # ── NRCarec 경보 ──────────────────────────────────────────────
    # BED 모델의 POS(3=걸터앉음, 4=낙상), FALL 모델의 pose(4=낙상)를 본다.
    # 레이더가 1초마다 보내므로 should_send 로 반복 발송을 막는다.
    try:
        _pos = record.get("POS") if is_bed else record.get("pose")
        _pos = int(_pos) if _pos is not None else None
        _kind = {3: "bedside", 4: "fall"}.get(_pos)
        # FALL 모델에는 걸터앉음이 없다(2=재실/4=낙상/5=자리비움).
        if _kind and not (is_fall and _kind == "bedside"):
            _sn = record.get("MAC") or record.get("macAddress") or "radar"
            if should_send(_sn, _kind):
                send_alert(_kind, room="421", patient_name="심영순", device_id=_sn)
    except Exception as _e:
        # 알림이 실패해도 센서 수신은 계속돼야 한다.
        print(f"[NRCarec] 경보 발송 실패: {_e}")

'''


def main():
    if not os.path.exists(APP):
        sys.exit(f'{APP} 가 없다. emfit_server 폴더에서 실행할 것.')

    src = io.open(APP, encoding='utf-8').read()

    if 'nrcarec_alert' in src:
        print('이미 적용되어 있다. 아무것도 하지 않음.')
        return

    if IMPORT_ANCHOR not in src:
        sys.exit(f'기준점을 못 찾았다: {IMPORT_ANCHOR!r}')
    if src.count(CALL_ANCHOR) != 1:
        sys.exit(f'응답 부분을 정확히 하나 찾지 못했다 (찾은 수: {src.count(CALL_ANCHOR)})')

    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    backup = f'{APP}.bak_{stamp}'
    shutil.copy2(APP, backup)
    print(f'백업: {backup}')

    out = src.replace(IMPORT_ANCHOR, IMPORT_ANCHOR + IMPORT_LINE, 1)
    out = out.replace(CALL_ANCHOR, CALL_BLOCK + CALL_ANCHOR, 1)
    io.open(APP, 'w', encoding='utf-8').write(out)

    # 문법이 깨졌으면 되돌린다. 서버가 안 뜨는 것보다 낫다.
    try:
        ast.parse(out)
    except SyntaxError as e:
        shutil.copy2(backup, APP)
        sys.exit(f'문법 오류가 나서 되돌렸다: {e}')

    print('적용 완료. 문법 검사 통과.')
    print('  1) sudo systemctl restart emfit')
    print('  2) sudo journalctl -u emfit -f | grep NRCarec')


if __name__ == '__main__':
    main()
