/**
 * Care Note 기록 누락 알림 발송 스크립트.
 *
 * GitHub Actions가 주기적으로 실행한다(.github/workflows/notify.yml).
 * Firestore의 settings/notifications 규칙을 읽어, 오늘 기록이 빠진 환자를 찾아
 * 등록된 모든 기기(push_tokens)로 FCM 푸시를 보낸다.
 *
 * 설계 메모
 * - 서비스 계정으로 접근하므로 Firestore 보안 규칙을 거치지 않는다.
 * - 알림은 반드시 data-only 로 보낸다. notification 필드를 같이 보내면
 *   브라우저가 자동으로 한 번 띄우고 서비스워커가 또 띄워 두 번 뜬다.
 * - 같은 알림을 15분마다 반복해 보내지 않도록 notification_log 에 발송 기록을 남긴다.
 */

const admin = require('firebase-admin');

// ---------- 상수 ----------

// 간호일 경계(오전 7시). lib/utils/care_date.dart 의 careDayStartHour 와 반드시 같아야 한다.
const CARE_DAY_START_HOUR = 7;

// 병동은 한국시간으로 움직인다. GitHub Actions 러너는 UTC라 직접 환산한다.
const KST_OFFSET_MINUTES = 9 * 60;

const MEALS = [
  { key: 'breakfast', label: '아침' },
  { key: 'lunch', label: '점심' },
  { key: 'dinner', label: '저녁' },
];

// ---------- 시간 유틸 ----------

/** 지금 시각을 한국시간 기준의 벽시계 값으로 변환한다. */
function nowKst() {
  const now = new Date();
  return new Date(now.getTime() + KST_OFFSET_MINUTES * 60 * 1000);
}

/** 간호일 날짜 키(YYYY-MM-DD). 07:00 이전은 전날로 친다. */
function careDateKey(kst) {
  const shifted = new Date(kst.getTime() - CARE_DAY_START_HOUR * 60 * 60 * 1000);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, '0');
  const d = String(shifted.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** 'HH:mm' → 자정 기준 분. 잘못된 값이면 null. */
function parseHhMm(text, fallbackMinutes) {
  if (typeof text !== 'string') return fallbackMinutes;
  const parts = text.split(':');
  if (parts.length !== 2) return fallbackMinutes;
  const h = Number(parts[0]);
  const m = Number(parts[1]);
  if (!Number.isInteger(h) || !Number.isInteger(m)) return fallbackMinutes;
  if (h < 0 || h > 23 || m < 0 || m > 59) return fallbackMinutes;
  return h * 60 + m;
}

/** 한국시간 기준 '자정으로부터 몇 분'인지. */
function minutesOfDay(kst) {
  return kst.getUTCHours() * 60 + kst.getUTCMinutes();
}

/**
 * 지금이 야간인지. 야간은 자정을 넘길 수 있어(예: 22:00~06:00) 구간을 두 갈래로 본다.
 */
function isNight(nowMinutes, startMinutes, endMinutes) {
  if (startMinutes === endMinutes) return false;
  if (startMinutes < endMinutes) {
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }
  return nowMinutes >= startMinutes || nowMinutes < endMinutes;
}

// ---------- 메인 ----------

async function main() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) {
    console.error('FIREBASE_SERVICE_ACCOUNT 시크릿이 없습니다.');
    process.exit(1);
  }

  admin.initializeApp({
    credential: admin.credential.cert(JSON.parse(raw)),
  });

  const db = admin.firestore();

  const settingsSnap = await db.doc('settings/notifications').get();
  const settings = settingsSnap.exists ? settingsSnap.data() : {};

  if (settings.enabled === false) {
    console.log('알림이 꺼져 있습니다(enabled=false). 종료.');
    return;
  }

  const kst = nowKst();
  const dateKey = careDateKey(kst);
  const nowMinutes = minutesOfDay(kst);

  console.log(`실행 시각(KST): ${kst.toISOString().slice(11, 16)}, 간호일: ${dateKey}`);

  const mealChecks = settings.mealChecks || {};
  const output = settings.output || {};

  const mealDeadlines = {
    breakfast: parseHhMm(mealChecks.breakfast, 10 * 60),
    lunch: parseHhMm(mealChecks.lunch, 14 * 60),
    dinner: parseHhMm(mealChecks.dinner, 20 * 60),
  };

  const outputDayHours = Number(output.dayHours) > 0 ? Number(output.dayHours) : 4;
  const outputNightHours = Number(output.nightHours) > 0 ? Number(output.nightHours) : 8;
  const nightStart = parseHhMm(output.nightStart, 22 * 60);
  const nightEnd = parseHhMm(output.nightEnd, 6 * 60);

  const outputThresholdHours = isNight(nowMinutes, nightStart, nightEnd)
    ? outputNightHours
    : outputDayHours;

  // ---------- 데이터 로드 ----------

  const [patientsSnap, mealSnap, outputSnap, tokensSnap] = await Promise.all([
    db.collection('patients').get(),
    db.collection('meal_records').where('date', '==', dateKey).get(),
    db.collection('output_records').where('date', '==', dateKey).get(),
    db.collection('push_tokens').get(),
  ]);

  const tokens = tokensSnap.docs.map((d) => d.id);
  if (tokens.length === 0) {
    console.log('등록된 기기가 없습니다. 종료.');
    return;
  }

  // 환자별 오늘 식사 기록 여부
  const mealsByPatient = new Map();
  for (const doc of mealSnap.docs) {
    const data = doc.data();
    const pid = String(data.patientId || '');
    if (!pid) continue;
    if (!mealsByPatient.has(pid)) mealsByPatient.set(pid, new Set());
    mealsByPatient.get(pid).add(String(data.mealType || ''));
  }

  // 환자별 마지막 배설 기록 시각
  const lastOutputByPatient = new Map();
  for (const doc of outputSnap.docs) {
    const data = doc.data();
    const pid = String(data.patientId || '');
    if (!pid) continue;
    const ts = data.createdAt;
    if (!ts || typeof ts.toDate !== 'function') continue;
    const at = ts.toDate();
    const prev = lastOutputByPatient.get(pid);
    if (!prev || at > prev) lastOutputByPatient.set(pid, at);
  }

  // ---------- 보낼 알림 모으기 ----------

  const pending = [];

  for (const doc of patientsSnap.docs) {
    const patient = doc.data();
    if (patient.isActive === false) continue;

    const pid = doc.id;
    const name = String(patient.name || '환자');
    const room = String(patient.room || '').replace('호', '').trim();
    const who = room ? `${room}호 ${name}님` : `${name}님`;

    // 식사: 확인 시각이 지났는데 기록이 없으면
    const recorded = mealsByPatient.get(pid) || new Set();
    for (const meal of MEALS) {
      const deadline = mealDeadlines[meal.key];
      if (nowMinutes < deadline) continue;
      if (recorded.has(meal.key)) continue;

      pending.push({
        // 같은 환자·같은 끼니는 간호일당 한 번만 보낸다.
        logId: `${pid}_${dateKey}_meal_${meal.key}`,
        repeatAfterMs: null,
        tag: `meal_${pid}_${meal.key}`,
        title: '식사 기록 누락',
        body: `${who}의 ${meal.label} 식사 기록이 입력되지 않았습니다. 확인하여 기입해주세요.`,
        kind: 'meal',
        patientId: pid,
        patientName: name,
        room,
        dateKey,
      });
    }

    // 배설: 마지막 기록 이후 임계 시간을 넘겼으면
    const last = lastOutputByPatient.get(pid);
    const thresholdMs = outputThresholdHours * 60 * 60 * 1000;
    const elapsedMs = last ? Date.now() - last.getTime() : null;

    if (last && elapsedMs > thresholdMs) {
      const hours = Math.floor(elapsedMs / (60 * 60 * 1000));
      pending.push({
        // 계속 기록이 없으면 임계 시간마다 다시 알린다.
        logId: `${pid}_${dateKey}_output`,
        repeatAfterMs: thresholdMs,
        tag: `output_${pid}`,
        title: '배설 기록 확인',
        body: `${who}의 배설 기록이 ${hours}시간째 없습니다. 확인해주세요.`,
        kind: 'output',
        patientId: pid,
        patientName: name,
        room,
        dateKey,
      });
    }
  }

  if (pending.length === 0) {
    console.log('보낼 알림이 없습니다.');
    return;
  }

  // ---------- 중복 발송 걸러내기 ----------

  const logRefs = pending.map((p) => db.doc(`notification_log/${p.logId}`));
  const logSnaps = await db.getAll(...logRefs);

  const toSend = [];
  pending.forEach((item, i) => {
    const snap = logSnaps[i];
    if (!snap.exists) {
      toSend.push(item);
      return;
    }
    // 반복 알림이 아니면 한 번 보낸 뒤로는 건너뛴다.
    if (item.repeatAfterMs === null) return;

    const sentAt = snap.data().sentAt;
    if (!sentAt || typeof sentAt.toDate !== 'function') {
      toSend.push(item);
      return;
    }
    if (Date.now() - sentAt.toDate().getTime() >= item.repeatAfterMs) {
      toSend.push(item);
    }
  });

  if (toSend.length === 0) {
    console.log(`조건에 맞는 항목 ${pending.length}건은 모두 이미 발송됨. 종료.`);
    return;
  }

  // ---------- 발송 ----------

  const invalidTokens = new Set();

  for (const item of toSend) {
    // data-only 로 보낸다. 표시는 서비스워커(onBackgroundMessage)가 담당한다.
    const message = {
      tokens,
      data: {
        title: item.title,
        body: item.body,
        tag: item.tag,
        url: '/',
      },
      webpush: {
        headers: { Urgency: 'high', TTL: '3600' },
      },
    };

    const res = await admin.messaging().sendEachForMulticast(message);
    console.log(`발송: ${item.body} → 성공 ${res.successCount} / 실패 ${res.failureCount}`);

    res.responses.forEach((r, i) => {
      if (r.success) return;
      const code = r.error && r.error.code;
      // 더 이상 유효하지 않은 토큰은 정리한다(기기 해지, 앱 삭제 등).
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-argument' ||
        code === 'messaging/invalid-registration-token'
      ) {
        invalidTokens.add(tokens[i]);
      } else {
        console.error(`  토큰 실패(${code}):`, r.error && r.error.message);
      }
    });

    await db.doc(`notification_log/${item.logId}`).set({
      sentAt: admin.firestore.Timestamp.now(),
      title: item.title,
      body: item.body,
      kind: item.kind,
      patientId: item.patientId,
      patientName: item.patientName,
      room: item.room,
      date: item.dateKey,
      successCount: res.successCount,
      failureCount: res.failureCount,
    });
  }

  // ---------- 죽은 토큰 정리 ----------

  if (invalidTokens.size > 0) {
    const batch = db.batch();
    for (const t of invalidTokens) {
      batch.delete(db.doc(`push_tokens/${t}`));
    }
    await batch.commit();
    console.log(`만료된 토큰 ${invalidTokens.size}건 삭제.`);
  }
}

main().catch((e) => {
  console.error('알림 발송 중 오류:', e);
  process.exit(1);
});
