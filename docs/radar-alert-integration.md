# AI Radar 경보를 NRCarec 으로 보내기

emfit_server(Jetson) 가 걸터앉음·낙상을 감지한 **그 순간** NRCarec 으로 알린다.

## 왜 이 구조인가

NRCarec 은 Firebase Hosting 에 올라간 정적 웹앱이라 **서버가 없다.** POST 를 받을
수단이 없으므로 레이더 API 를 직접 수신할 수 없다. 보내는 쪽은 emfit_server 다.

```
AI Radar ──→ emfit_server (이미 수신 중, 24시간 상시)
                  │  ← 감지한 순간
                  ├──→ Firestore notification_log 에 기록
                  │        └─→ NRCarec 이 구독 → 소리 + 확인 팝업 (앱 열려 있을 때)
                  └──→ FCM 발송 → 잠금화면 알림 (앱 꺼져 있을 때)
```

둘 다 하는 이유:
- **Firestore 만** 하면 앱이 꺼져 있을 때 아무도 모른다.
- **FCM 만** 하면 알림 기록에 남지 않고, 대시보드가 소리를 낼 근거가 없다.

Cloud Functions 로 Firestore 변화를 감지해 푸시하는 방법은 **Blaze(유료)** 라 쓸 수 없고,
NRCarec 의 GitHub Actions 스케줄러는 **30분~1시간 지연** 이라 낙상에 의미가 없다.
그래서 상시 가동 중인 emfit_server 가 직접 보내는 것이 유일한 길이다.

## 준비물

```bash
pip install firebase-admin
```

Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성(JSON).
**비공개 키다. 저장소에 커밋하지 말고** 파일 경로나 환경변수로 넣는다.

## 붙여 쓸 코드

```python
# nrcarec_alert.py
"""AI Radar 경보를 NRCarec 으로 보낸다."""

import os
import datetime
import firebase_admin
from firebase_admin import credentials, firestore, messaging

_app = None

def _init():
    global _app
    if _app is None:
        cred = credentials.Certificate(os.environ['NRCAREC_SERVICE_ACCOUNT'])
        _app = firebase_admin.initialize_app(cred, name='nrcarec')
    return _app


# 종류별 표시 정보. NRCarec 이 이 값으로 아이콘과 색을 고른다.
KINDS = {
    'fall':    ('낙상 감지', '/icons/notify-fall.png'),
    'bedside': ('걸터앉음 감지', '/icons/notify-bedside.png'),
}


def send_alert(kind, room, patient_name, device_id, detail=''):
    """
    kind         : 'fall' 또는 'bedside'
    room         : '421'      (호 빼고 숫자만)
    patient_name : '환자A'
    device_id    : 레이더 기기 식별자. 같은 기기의 같은 경보를 묶는 데 쓴다.
    detail       : 덧붙일 설명(선택)
    """
    _init()
    title, icon = KINDS[kind]

    who = f'{room}호 {patient_name}님' if room else f'{patient_name}님'
    body = f'{who} · {title[:-3]}이 감지되었습니다.'
    if detail:
        body += f' {detail}'

    # 같은 기기·같은 종류는 하나로 묶는다. 알림창에 쌓이지 않고 최신 것으로 바뀐다.
    tag = f'{kind}_{device_id}'

    db = firestore.client(app=_app)

    # 1) 기록 — NRCarec 이 구독해 소리와 팝업을 띄우고, 알림 기록에도 남는다.
    doc_id = f'{tag}_{int(datetime.datetime.now().timestamp())}'
    db.collection('notification_log').document(doc_id).set({
        'sentAt': firestore.SERVER_TIMESTAMP,
        'kind': kind,               # 'fall' | 'bedside'
        'title': title,
        'body': body,
        'room': room,
        'patientName': patient_name,
        'deviceId': device_id,
    })

    # 2) 푸시 — 앱이 꺼져 있어도 닿는다.
    tokens = [d.id for d in db.collection('push_tokens').stream()]
    if not tokens:
        return 0

    res = messaging.send_each_for_multicast(
        messaging.MulticastMessage(
            tokens=tokens,
            # 반드시 data 만 쓴다. notification 을 같이 보내면 브라우저가 한 번,
            # 서비스워커가 또 한 번 띄워 알림이 두 번 뜬다.
            data={
                'title': title,
                'body': body,
                'kind': kind,
                'icon': icon,
                'tag': tag,
                'url': '/',
            },
            webpush=messaging.WebpushConfig(
                headers={'Urgency': 'high', 'TTL': '600'},
            ),
        ),
        app=_app,
    )

    # 만료된 토큰 정리
    for token, r in zip(tokens, res.responses):
        if not r.success and r.exception and 'registration-token-not-registered' in str(r.exception):
            db.collection('push_tokens').document(token).delete()

    return res.success_count
```

## 감지 지점에서 부르기

```python
from nrcarec_alert import send_alert

# 낙상 판정이 확정된 곳에서 한 번만
send_alert('fall', room='421', patient_name='환자A', device_id=sn)
```

## 반드시 지켜야 할 것

**한 번만 보낼 것.** 낙상 모델 레이더는 **1초마다** 상태를 보낸다. 그대로 두면
낙상이 10초 이어질 때 알림이 10번 간다. 감지 쪽에서 상태가 **바뀌는 순간에만**
부르거나, 같은 `device_id` + `kind` 는 일정 시간 안에 다시 보내지 않도록 막는다.

```python
_last_sent = {}   # (device_id, kind) -> timestamp

def should_send(device_id, kind, cooldown_sec=180):
    key = (device_id, kind)
    now = datetime.datetime.now().timestamp()
    if now - _last_sent.get(key, 0) < cooldown_sec:
        return False
    _last_sent[key] = now
    return True
```

## NRCarec 쪽 동작

| 상황 | 동작 |
|---|---|
| 앱·대시보드 열려 있음 | **경보음이 울리고**, 확인을 누르기 전까지 사라지지 않는 팝업 |
| 앱 꺼져 있음 | 잠금화면 푸시 알림. 확인 전까지 유지(안드로이드·PC) |
| 나중에 | 종 아이콘의 알림 기록에 남음 |

**웹 푸시는 알림음을 지정할 수 없다**(브라우저가 무시한다). 앱이 꺼져 있을 때는
기기 기본 알림음만 난다. 우리가 만든 경보음은 **화면이 열려 있을 때만** 난다.
그래서 스테이션 대시보드를 켜 두는 것이 사실상 필수다.

iOS 홈화면 PWA 는 `requireInteraction` 을 지원하지 않아, 꺼져 있을 때 온 알림은
일반 알림처럼 사라질 수 있다.

## 환자 등록

경보만 목적이면 NRCarec 에 환자를 등록하지 않아도 된다. `room` 과 `patient_name`
을 문구로 실어 보내면 그대로 표시된다.
그 환자의 섭취·배설도 NRCarec 에서 기록하려면 그때 환자로 등록한다.
