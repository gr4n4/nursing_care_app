/* Care Note 웹 푸시 수신용 서비스워커.
 *
 * 앱이 꺼져 있거나 브라우저가 백그라운드일 때 알림을 띄우는 주체다.
 * 이 파일은 Flutter 빌드에 그대로 복사되며, 반드시 사이트 루트
 * (/firebase-messaging-sw.js) 에 있어야 브라우저가 등록해 준다.
 *
 * 스케줄러는 반드시 "data-only" 메시지로 보낼 것.
 * notification 필드를 같이 보내면 브라우저가 자동으로 한 번 띄우고
 * onBackgroundMessage 에서 또 띄워 알림이 두 번 뜬다.
 */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

// 새 서비스워커를 즉시 활성화(activate)한다.
// 이게 없으면 새로 설치된 워커가 "대기(waiting)" 상태로 머물고, 지금 열려 있는
// 탭은 이전 워커(또는 워커 없음)의 통제 하에 남는다. getToken()은 서비스워커가
// 이 탭을 실제로 장악(active + controlling)할 때까지 기다리므로, 탭을 새로고침하기
// 전까지 "처리 중"에서 영원히 멈춘 것처럼 보인다.
self.addEventListener('install', function (event) {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(clients.claim());
});

firebase.initializeApp({
  apiKey: 'AIzaSyCQM5AgZ53fIQYun3gdNSBfCG-_69Nkld8',
  appId: '1:616337186483:web:d18da56f0dfd5828965ac6',
  messagingSenderId: '616337186483',
  projectId: 'nursing-care-app-702b7',
  authDomain: 'nursing-care-app-702b7.firebaseapp.com',
  storageBucket: 'nursing-care-app-702b7.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  const data = payload.data || {};

  const title = data.title || 'Care Note';
  const options = {
    body: data.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    // 같은 환자·같은 종류의 알림이 쌓이지 않고 최신 것으로 갱신되게 한다.
    tag: data.tag || 'carenote',
    renotify: true,
    requireInteraction: true,
    data: { url: data.url || '/' },
  };

  return self.registration.showNotification(title, options);
});

// 알림을 누르면 이미 열려 있는 Care Note 탭으로 이동하고, 없으면 새로 연다.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();

  const target = (event.notification.data && event.notification.data.url) || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
      for (const client of list) {
        if ('focus' in client) {
          if ('navigate' in client) client.navigate(target);
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(target);
    })
  );
});
