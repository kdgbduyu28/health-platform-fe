// Shows the Web Push messages sent by the send-push Edge Function
// (health-platform-be), and opens the app where one points when tapped.
//
// The app registers this under ./push/, so it never competes with Flutter's
// own service worker for the page. That also means it controls no page: an
// open tab is asked to navigate by message (BrowserPush.onNotificationOpened)
// rather than navigated directly.
//
// Kept identical in all four apps' web/ folders.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(
    self.registration.showNotification(data.title || 'Clinic update', {
      body: data.body || '',
      // Same tag, same notification: a resend replaces rather than repeats.
      tag: data.tag,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      data: { link: data.link || '/' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const link = (event.notification.data && event.notification.data.link) || '/';
  event.waitUntil(
    (async () => {
      const tabs = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      const tab = tabs.find((c) => new URL(c.url).origin === self.location.origin);
      if (tab) {
        tab.postMessage({ type: 'open-link', link });
        return tab.focus();
      }
      return self.clients.openWindow(new URL(link, self.location.origin).href);
    })(),
  );
});
