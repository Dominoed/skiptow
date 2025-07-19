const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

function haversineDistance(loc1, loc2) {
  const toRad = val => (val * Math.PI) / 180;
  const R = 6371000; // meters
  const dLat = toRad(loc2.lat - loc1.lat);
  const dLng = toRad(loc2.lng - loc1.lng);
  const lat1 = toRad(loc1.lat);
  const lat2 = toRad(loc2.lat);

  const a = Math.sin(dLat / 2) ** 2 +
            Math.cos(lat1) * Math.cos(lat2) *
            Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

exports.notifyNewInvoice = functions.firestore
  .document('invoices/{invoiceId}')
  .onCreate(async (snap, context) => {
    const invoice = snap.data();
    if (!invoice) return null;

    const mechanicId = invoice.mechanicId;
    const customerId = invoice.customerId;
    if (!customerId) return null;

    const customerSnap = await admin.firestore()
      .collection('users')
      .doc(customerId)
      .get();
    const customerUsername = customerSnap.exists && customerSnap.data().username
      ? customerSnap.data().username
      : 'customer';

    let mechanicIds = [];
    if (!mechanicId || mechanicId === 'any') {
      // Broadcast to nearby active mechanics
      const mechanicsSnap = await admin.firestore()
        .collection('users')
        .where('role', '==', 'mechanic')
        .where('isActive', '==', true)
        .get();
      mechanicsSnap.forEach(doc => {
        const data = doc.data();
        if (data.unavailable === true) return;
        if (!data.location || typeof data.radiusMiles !== 'number') return;
        if (!invoice.location) return;
        const dist = haversineDistance(invoice.location, data.location);
        const radius = data.radiusMiles * 1609.34;
        if (dist <= radius) {
          mechanicIds.push(doc.id);
        }
      });
      // Update the invoice with candidate list and clear mechanicId
      await snap.ref.update({
        mechanicId: null,
        mechanicCandidates: mechanicIds,
        mechanicResponded: [],
      });
    } else {
      mechanicIds = [mechanicId];
    }

    const tokens = [];
    for (const id of mechanicIds) {
      const userDoc = await admin.firestore().collection('users').doc(id).get();
      if (!userDoc.exists) continue;
      const uData = userDoc.data();
      if (uData.isActive !== true) continue;
      if (uData.unavailable === true) continue;
      const tokensSnap = await admin
        .firestore()
        .collection('users')
        .doc(id)
        .collection('tokens')
        .get();
      tokensSnap.forEach(t => tokens.push(t.id));
    }

    if (tokens.length === 0) return null;

    const broadcast = !mechanicId || mechanicId === 'any';
    const message = {
      notification: {
        title: 'New Service Request',
        body: broadcast
          ? 'New nearby service request!'
          : `You\u2019ve received a new service request from ${customerUsername}.`
      },
      tokens
    };

    await admin.messaging().sendEachForMulticast(message);
    return null;
  });

exports.notifyInvoiceUpdate = functions.firestore
  .document('invoices/{invoiceId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return null;

    const customerId = after.customerId;
    if (!customerId) return null;

    const tokensSnap = await admin
      .firestore()
      .collection('users')
      .doc(customerId)
      .collection('tokens')
      .get();
    const tokens = tokensSnap.docs.map(t => t.id);
    if (tokens.length === 0) return null;

    const promises = [];

    const cand = Array.isArray(after.mechanicCandidates)
      ? after.mechanicCandidates
      : [];
    const responded = Array.isArray(after.mechanicResponded)
      ? after.mechanicResponded
      : [];

    const beforeRespLen = Array.isArray(before.mechanicResponded)
      ? before.mechanicResponded.length
      : 0;

    if (before.paymentStatus !== after.paymentStatus) {
      const invoiceNumber = after.invoiceNumber || context.params.invoiceId;
      promises.push(
        admin.messaging().sendEachForMulticast({
          notification: {
            title: 'Invoice Update',
            body: `Your invoice ${invoiceNumber} is now marked as ${after.paymentStatus}.`
          },
          tokens
        })
      );
    }

    if (before.mechanicAccepted !== after.mechanicAccepted) {
      const mech = after.mechanicUsername || 'Mechanic';
      promises.push(
        admin.messaging().sendEachForMulticast({
          notification: {
            title: 'Mechanic Accepted',
            body: `${mech} accepted your request.`
          },
          tokens
        })
      );
    }

    if (
      !after.mechanicId &&
      cand.length > 0 &&
      responded.length === cand.length &&
      responded.length !== beforeRespLen
    ) {
      promises.push(
        admin.messaging().sendEachForMulticast({
          notification: {
            title: 'Service Request Update',
            body: 'All nearby mechanics declined your request.'
          },
          tokens
        })
      );
    }

    if (promises.length === 0) return null;
    await Promise.all(promises);
    return null;
  });

exports.notifyBroadcastMessage = functions.firestore
  .document('notifications/{userId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data || data.sendFcm === false) return null;
    const userId = context.params.userId;
    const tokensSnap = await admin
      .firestore()
      .collection('users')
      .doc(userId)
      .collection('tokens')
      .get();
    const tokens = tokensSnap.docs.map(t => t.id);
    if (tokens.length === 0) return null;
    await admin.messaging().sendEachForMulticast({
      notification: {
        title: data.title || 'New Message',
        body: data.body || '',
      },
      tokens,
    });
    return null;
  });

exports.sendPaymentReminders = functions.pubsub
  .schedule('every 24 hours')
  .timeZone('Etc/UTC')
  .onRun(async () => {
    const db = admin.firestore();
    const snapshot = await db
      .collection('invoices')
      .where('paymentStatus', '==', 'overdue')
      .get();

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const customerId = data.customerId;
      if (!customerId) continue;

      const invoiceNumber = data.invoiceNumber || doc.id;
      let body = `Invoice #${invoiceNumber} is overdue. Please pay as soon as possible.`;
      const createdAt = data.createdAt instanceof admin.firestore.Timestamp
        ? data.createdAt.toDate()
        : null;
      if (createdAt) {
        const days = Math.floor((Date.now() - createdAt.getTime()) / (1000 * 60 * 60 * 24));
        if (days > 37) {
          body = `Invoice #${invoiceNumber} is over 30 days overdue. Please pay immediately.`;
        }
      }

      const messageData = {
        title: 'Payment Reminder',
        body,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db
        .collection('notifications')
        .doc(customerId)
        .collection('messages')
        .add(messageData);

      const tokensSnap = await db
        .collection('users')
        .doc(customerId)
        .collection('tokens')
        .get();
      const tokens = tokensSnap.docs.map(t => t.id);
      if (tokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
          notification: {
            title: messageData.title,
            body: messageData.body,
          },
          tokens,
        });
      }
    }

    return null;
  });

exports.notifyInvoiceMessage = functions.firestore
  .document('invoices/{invoiceId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;

    const invoiceId = context.params.invoiceId;
    const fromUserId = data.fromUserId;
    if (!invoiceId || !fromUserId) return null;

    const db = admin.firestore();
    const invoiceSnap = await db.collection('invoices').doc(invoiceId).get();
    const invoice = invoiceSnap.data();
    if (!invoice) return null;

    const customerId = invoice.customerId;
    const mechanicId = invoice.mechanicId;
    let recipientId = null;

    if (fromUserId === mechanicId) {
      recipientId = customerId;
    } else if (fromUserId === customerId) {
      recipientId = mechanicId;
    }

    if (!recipientId) return null;

    const recipientDoc = await db.collection('users').doc(recipientId).get();
    if (!recipientDoc.exists || recipientDoc.data().role === 'admin') return null;

    const tokensSnap = await db
      .collection('users')
      .doc(recipientId)
      .collection('tokens')
      .get();
    const tokens = tokensSnap.docs.map(t => t.id);
    if (tokens.length === 0) return null;

    await admin.messaging().sendEachForMulticast({
      notification: {
        title: 'New Message in Service Request',
        body: 'Tap to reply.'
      },
      data: {
        invoiceId,
        type: 'invoiceMessage'
      },
      tokens
    });

    return null;
  });

