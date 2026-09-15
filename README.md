# NRCarec

요양·병동 환자의 **섭취(식사·수분)와 배설을 기록하고, 수분 밸런스를 모니터링**하는 Flutter 앱입니다.

간호사는 휴대폰으로 환자별 기록을 남기고, 널스스테이션에서는 웹 대시보드로 병동 전체 현황을 한눈에 확인합니다. 여기에 **기록 누락 알림**, 레이더 센서의 **낙상·걸터앉음 경보**, 로봇을 통한 **물품 배송**이 붙어 있습니다.

현재 버전: **v2.1.0** (`lib/app_version.dart`)

---

## 주요 기능

### 기록 (모바일 · 간호사)
- **환자 등록/관리** — 환자 정보 등록, 목록 표시 여부 관리
- **식사 기록** — 주식(밥·진밥·된죽·죽·미음), 국, 반찬(고기·생선·계란·두부·포기김치·물김치)을 `0 · ¼ · ⅓ · ½ · 전체` 비율로 입력
- **섭취 경로별 4분류** — 경구식(구강섭취·관급식) / 비경구식(수액) / 수분섭취(음료 포함) / 기타섭취(과일). 분류별로 따로 열어 한 화면의 스크롤을 줄였습니다.
- **배설 기록** — 배뇨(자연배뇨·카테타·실금)와 배변, `계란 1개 = 50g` 환산 버튼 제공
- **간호 평가** — 부종·배변 타입 기록

### 모니터링 (웹 · 널스스테이션)
- 병동 전체 환자의 금일 식사·수분·배설 현황 표
- **I/O 밸런스 알림** — `섭취 수분 − 소변량`이 **±500mL**를 벗어나면 경고 표시
- **환자 하루 보기** — 한 환자의 밸런스 → 식사/배설 상세 → 특이사항을 한 화면에 모아 봅니다
- **엑셀 내보내기** — 간호과 '섭취·배설 기록지' 양식의 칸 순서를 그대로 따른 `기록지` 시트와, 근거 확인용 `상세내역` 시트

### 알림
- **기록 누락 알림** — 15분마다 도는 GitHub Actions 스케줄러(`scripts/notify.js`)가 기록이 빠진 환자를 찾아 푸시(FCM)를 보냅니다. 발송 시각·임계값은 코드가 아니라 앱의 **알림 설정** 화면(Firestore `settings/notifications`)에서 바꿉니다.
- **센서 경보(낙상·걸터앉음)** — 레이더가 감지한 순간 `emfit_server`가 보냅니다. 화면이 열려 있으면 **경보음과 확인 전까지 사라지지 않는 팝업**, 꺼져 있으면 잠금화면 푸시. 자세한 규약은 [docs/radar-alert-integration.md](docs/radar-alert-integration.md)에 있습니다.
- **알림 기록** — 상단 종 버튼에서 지금까지 발송된 알림을 한 건씩 펼쳐 봅니다

### 물품 배송 (로봇)
간호사가 앱에서 요청하면 널스스테이션에서 배차하고, 로봇이 물품을 실어 나릅니다.

```
requested ─[수락]→ accepted ─[출발]→ delivering ─[수령 확인]→ done
                      ↓                   ↓                    ↓
                 at_loading           delivered             closed    ← 로봇이 찍는 값
```

사람이 누르는 것은 `accepted` / `delivering` / `done` / `canceled` 뿐이고, 로봇 도착 상태는 Firestore 규칙에서 사람이 못 쓰게 막아 두었습니다. 품목은 `settings/delivery_items`에서 읽어 앱을 다시 배포하지 않고 바꿀 수 있습니다. 보낼 위치는 **로봇이 켜질 때 `settings/delivery_rooms`에 써 둔 "갈 수 있는 곳"** 만 고르게 해서, 로봇이 못 가는 곳으로 요청이 가지 않습니다.

### 특징
- **음식별 수분함량 자동 계산** — 국립농업과학원의 1회 제공량·수분량 자료를 기준으로, 먹은 비율만큼 수분 섭취량을 자동 산출
- **간호일(care-day) 기준 07:00 리셋** — 자정이 아닌 오전 7시에 하루가 바뀝니다. 밤늦게 마신 수분과 새벽에 나온 배설이 같은 날로 묶여 밸런스가 어긋나지 않습니다.
- **접근성 고려** — 상태 표시에 색 + 아이콘 + 텍스트를 함께 사용해 색 구분이 어려운 사용자도 인지할 수 있도록 설계 (KS A ISO/TR 22411 참고). 색은 `lib/theme/app_colors.dart` 한 곳에 모으고 대비를 WCAG 2.1로 실측했습니다.

---

## 사용자 역할

| 역할 | 설명 |
|------|------|
| **간호사 (nurse)** | 환자 등록, 식사·수분·배설 기록, 물품 배송 요청 |
| **관리자 (admin)** | 대시보드 모니터링, 환자·간호사 명단 관리, 배차, 알림 설정 |

> 환자는 **로그인 계정이 아니라 데이터**입니다. 간호사/관리자가 환자를 등록해 관리합니다.

---

## 기술 스택

- **Flutter** (Dart) — Android / Web
- **Firebase**
  - Authentication — 간호사·관리자 로그인
  - Cloud Firestore — 환자 및 기록 데이터
  - Cloud Messaging (FCM) — 푸시 알림
  - Hosting — 웹 대시보드 배포
- **GitHub Actions** — 기록 누락 알림 스케줄러 (`.github/workflows/notify.yml`)

---

## 실행 방법

```bash
# 1. 의존성 설치
flutter pub get

# 2. 실행 (모바일)
flutter run

# 3. 실행 (웹)
flutter run -d chrome
```

> Firebase 프로젝트 설정(`firebase_options.dart`, `google-services.json`)이 포함되어 있어야 합니다.

배포 절차와 버전 올리는 규칙은 [BUILD.md](BUILD.md)를 보세요.

---

## 프로젝트 구조

```
lib/
├── main.dart                     앱 진입점 · 로그인 상태에 따른 화면 분기
├── app_version.dart              배포 버전 (pubspec.yaml 과 같은 값 유지)
├── firebase_options.dart         Firebase 설정
├── data/
│   └── food_table.dart           음식별 1회 제공량·수분함량 표, 밸런스 기준값
├── models/
│   ├── patient.dart              환자 모델
│   └── delivery_request.dart     물품 배송 요청 · 상태 흐름
├── theme/
│   └── app_colors.dart           색 팔레트 (단일 출처)
├── utils/
│   ├── care_date.dart            간호일(07:00 기준) 날짜 계산
│   ├── alert_center.dart         낙상·걸터앉음 경보 수신 (소리 + 확인 팝업)
│   ├── delivery_watcher.dart     새 배송 요청 감지 · 배차 메뉴 건수 표시
│   ├── push_messaging.dart       FCM 토큰 발급·등록
│   ├── notification_kind.dart    알림 종류별 아이콘·색 규칙
│   ├── record_export.dart        하루치 기록 엑셀 내보내기
│   └── feedback.dart             저장 완료 확인 표시
├── widgets/
│   └── notification_bell.dart    상단 종 버튼 · 안 읽음 표시
└── pages/
    ├── login_page.dart               로그인
    ├── nurse_register_page.dart      간호사 가입
    ├── nurse_home_page.dart          간호사 홈 (환자 목록·현황)
    ├── nurse_profile_edit_page.dart  간호사 정보 수정
    ├── input_choice_page.dart        식사/배설 기록 선택
    ├── intake_category_page.dart     섭취 경로 4분류 선택
    ├── intake_record_page.dart       섭취 기록 (식사·수분·과일)
    ├── output_record_page.dart       배설 기록
    ├── patient_register_page.dart    환자 등록
    ├── patient_list_page.dart        환자 목록
    ├── patient_detail_page.dart      환자 상세
    ├── patient_day_page.dart         환자 하루 기록 모아 보기
    ├── patient_profile_edit_page.dart 환자 정보 수정
    ├── station_page.dart             널스스테이션 대시보드 (웹)
    ├── admin_nurse_roster_page.dart  간호사 명단 관리
    ├── io_balance_page.dart          수분 밸런스 계산기
    ├── notification_settings_page.dart 알림 규칙 설정
    ├── notification_log_page.dart    발송된 알림 기록
    ├── delivery_request_page.dart    물품 배송 요청 (모바일)
    └── delivery_dispatch_page.dart   로봇 배차 (웹)
```

그 밖에 `scripts/`는 알림 스케줄러(Node.js), `docs/`는 외부 시스템 연동 문서, `firestore.rules`는 보안 규칙입니다.

### 데이터 구조 (Firestore)

| 컬렉션 | 내용 | 쓰는 쪽 |
|--------|------|--------|
| `users` | 간호사·관리자 계정 정보 (역할 포함) | 앱 |
| `patients` | 환자 정보 | 앱 |
| `meal_records` | 식사 기록 (환자·날짜·끼니 단위) | 앱 |
| `water_records` | 수분·과일 섭취 기록 | 앱 |
| `output_records` | 배설 기록 | 앱 |
| `daily_assessments` | 부종·배변 타입 등 간호 평가 (환자·날짜별 1문서) | 앱 |
| `settings` | 알림 규칙(`notifications`), 배송 품목(`delivery_items`), 배송 가능 위치(`delivery_rooms`) | 앱 · 로봇 브릿지(`delivery_rooms`) |
| `push_tokens` | FCM 기기 토큰 (문서 ID = 토큰) | 앱 / 스케줄러가 만료분 정리 |
| `notification_log` | 발송된 알림 기록 | 스케줄러 · `emfit_server` |
| `delivery_requests` | 물품 배송 요청 | 앱 · 로봇 브릿지 |
| `robot_state` | 로봇 위치·가동 상태 (`current` 한 문서) | 로봇 브릿지 (앱은 읽기만) |

---

## 함께 쓰는 시스템

이 앱은 서버가 없는 정적 웹앱이라 POST 를 받을 수 없습니다. 그래서 외부 시스템이 **Firestore 에 직접 쓰는** 방식으로 붙습니다.

| 시스템 | 사는 곳 | 하는 일 |
|---|---|---|
| `emfit_server` | 젯슨 (`/home/carerobot/emfit_server`) | AI Radar 수신 → 낙상·걸터앉음을 `notification_log` 와 FCM 으로 발송 |
| 로봇 브릿지 `nrcarec_bridge.py` | 로봇 (`colcon_ws_jy/scripts/`) | `delivery_requests` 를 보고 움직이고, 도착 상태와 `robot_state` 를 갱신 |

둘 다 이 저장소 밖에 있고, 이 저장소는 **연동 규약과 연동용 스크립트만** 들고 있습니다.

- [docs/radar-alert-integration.md](docs/radar-alert-integration.md) — 센서 경보 연동 규약과 붙여 쓸 파이썬 코드
- [docs/patch_app_py.py](docs/patch_app_py.py) — `emfit_server` 의 `app.py` 에 경보 발송을 끼워 넣는 스크립트 (**젯슨의 `emfit_server` 폴더에서** 실행)
- [test/alert_contract_test.dart](test/alert_contract_test.dart) — `emfit_server` 가 보내는 형식을 앱이 제대로 해석하는지 확인

### 작업 폴더 배치

개발 PC 에서는 돌봄 모니터링 관련 저장소를 한 폴더 아래 나란히 둡니다.

```
Monitoring/
├── nursing_care_app/     이 저장소 (NRCarec)
├── emfit_server/         Emfit·레이더 수집 서버 작업본
├── garmin/               Garmin 건강데이터 수집·분석
└── monitoring_tech/      돌봄 모니터링 기술·제품화 동향 조사 자료
```

각각 **독립된 git 저장소**이고 빌드상 서로를 참조하지 않습니다. 이 저장소는 어느 경로에 두어도 그대로 동작하므로, 폴더를 옮겼다면 `flutter pub get` 만 다시 돌리면 됩니다(`.dart_tool/`·`build/` 의 생성된 경로가 갱신됩니다).

---

## 현재 상태

- 1차 사용성 평가 완료, 2차 버전(v2.0.0)부터 간호과 실사용 중
- 레이더 센서(낙상·걸터앉음) 경보 연동 완료
- 물품 배송 로봇 연동 진행 중 (v2.1.0)
