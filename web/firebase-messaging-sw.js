// Firebase Cloud Messaging service worker for Sale Scout (web push).
// This file MUST live at the web root so the browser can register it as a
// background service worker. It receives pushes even when the tab is closed.

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAtjyE4YoU3ioHGvt3tKgbGsWBoQuLDigM',
  appId: '1:641515763749:web:349e009f652684c6ade7cc',
  messagingSenderId: '641515763749',
  projectId: 'sale-scout-ff2a5',
  authDomain: 'sale-scout-ff2a5.firebaseapp.com',
  storageBucket: 'sale-scout-ff2a5.firebasestorage.app',
});

// Initializing messaging is all that's needed: because the API sends a message
// that includes a `notification` payload, Firebase automatically displays it
// in the background. We deliberately do NOT add an onBackgroundMessage handler
// that calls showNotification — doing so displays a SECOND copy on top of
// Firebase's automatic one (the duplicate-notification bug).
firebase.messaging();

// Activate this updated service worker immediately, so cache doesn't get in the
// way of picking up changes.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
