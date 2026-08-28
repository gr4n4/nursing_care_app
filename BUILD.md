# 배포 방법

```bash
flutter build web --wasm
firebase deploy --only hosting --project nursing-care-app-702b7
```

## `--wasm` 를 반드시 붙이는 이유

붙이지 않으면 첫 로딩에 받는 양이 크게 늘어난다.

| 경로 | 첫 로딩 크기 |
|---|---|
| `--wasm` (최신 브라우저) | **6.3 MB** |
| 기본 JS (구형 브라우저) | 10.3 MB |

`--wasm` 은 두 벌을 모두 만들어 두고, 브라우저가 WasmGC 를 지원하면 가벼운
쪽을, 아니면 JS 쪽을 자동으로 고른다. 그래서 구형 브라우저에서도 안전하다.
실행 속도도 wasm 쪽이 빠르다.

## 배포 전 확인

```bash
flutter analyze lib          # 에러 0건
grep -c firebase_messaging build/web/main.dart.js   # 0이면 FCM 누락
```

`firebase_messaging` 이 0이면 증분 빌드 캐시가 웹 플러그인 등록을 빠뜨린 것이다.
`flutter clean` 후 다시 빌드해야 한다.
