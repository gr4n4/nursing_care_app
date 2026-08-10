# Care Note (케어노트)

요양·병동 환자의 **섭취(식사·수분)와 배설을 기록하고, 수분 밸런스를 모니터링**하는 Flutter 앱입니다.

간호사는 휴대폰으로 환자별 기록을 남기고, 널스스테이션에서는 웹 대시보드로 병동 전체 현황을 한눈에 확인합니다.

---

## 주요 기능

### 기록 (모바일 · 간호사)
- **환자 등록/관리** — 환자 정보 등록, 목록 표시 여부 관리
- **식사 기록** — 주식(밥·진밥·된죽·죽·미음), 국, 반찬(고기·생선·계란·두부·포기김치·물김치)을 `0 · ¼ · ⅓ · ½ · 전체` 비율로 입력
- **수분 · 유제품** — 물, 우유, 요구르트, 두유를 비율로 입력
- **기타 섭취(과일)** — 과일 18종
- **배설 기록** — 배뇨(자연배뇨·카테타·실금)와 배변, `계란 1개 = 50g` 환산 버튼 제공

### 모니터링 (웹 · 널스스테이션)
- 병동 전체 환자의 금일 식사·수분·배설 현황 표
- **I/O 밸런스 알림** — `섭취 수분 − 소변량`이 **±500mL**를 벗어나면 경고 표시

### 특징
- **음식별 수분함량 자동 계산** — 국립농업과학원의 1회 제공량·수분량 자료를 기준으로, 먹은 비율만큼 수분 섭취량을 자동 산출
- **간호일(care-day) 기준 07:00 리셋** — 자정이 아닌 오전 7시에 하루가 바뀝니다. 밤늦게 마신 수분과 새벽에 나온 배설이 같은 날로 묶여 밸런스가 어긋나지 않습니다.
- **접근성 고려** — 상태 표시에 색 + 아이콘 + 텍스트를 함께 사용해 색 구분이 어려운 사용자도 인지할 수 있도록 설계 (KS A ISO/TR 22411 참고)

---

## 사용자 역할

| 역할 | 설명 |
|------|------|
| **간호사 (nurse)** | 환자 등록, 식사·수분·배설 기록 |
| **관리자 (admin)** | 대시보드 모니터링, 환자·간호사 명단 관리 |

> 환자는 **로그인 계정이 아니라 데이터**입니다. 간호사/관리자가 환자를 등록해 관리합니다.

---

## 기술 스택

- **Flutter** (Dart) — Android / Web
- **Firebase**
  - Authentication — 간호사·관리자 로그인
  - Cloud Firestore — 환자 및 기록 데이터
  - Hosting — 웹 대시보드 배포

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

---

## 프로젝트 구조

```
lib/
├── main.dart                     앱 진입점 · 로그인 상태에 따른 화면 분기
├── firebase_options.dart         Firebase 설정
├── data/
│   └── food_table.dart           음식별 1회 제공량·수분함량 표, 밸런스 기준값
├── models/
│   └── patient.dart              환자 모델
├── utils/
│   └── care_date.dart            간호일(07:00 기준) 날짜 계산
└── pages/
    ├── login_page.dart               로그인
    ├── nurse_register_page.dart      간호사 가입
    ├── nurse_home_page.dart          간호사 홈 (환자 목록·현황)
    ├── nurse_profile_edit_page.dart  간호사 정보 수정
    ├── input_choice_page.dart        식사/배설 기록 선택
    ├── intake_record_page.dart       섭취 기록 (식사·수분·과일)
    ├── output_record_page.dart       배설 기록
    ├── patient_register_page.dart    환자 등록
    ├── patient_list_page.dart        환자 목록
    ├── patient_detail_page.dart      환자 상세
    ├── patient_profile_edit_page.dart 환자 정보 수정
    ├── station_page.dart             널스스테이션 대시보드 (웹)
    ├── admin_nurse_roster_page.dart  간호사 명단 관리
    └── io_balance_page.dart          수분 밸런스 계산기
```

### 데이터 구조 (Firestore)

| 컬렉션 | 내용 |
|--------|------|
| `users` | 간호사·관리자 계정 정보 (역할 포함) |
| `patients` | 환자 정보 |
| `meal_records` | 식사 기록 (환자·날짜·끼니 단위) |
| `water_records` | 수분·과일 섭취 기록 |
| `output_records` | 배설 기록 |

---

## 현재 상태

- 1차 사용성 평가 완료
- 레이더 센서 · Emfit QS 등 외부 센서 연동 검토 중
