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
      });
    } else {
      mechanicIds = [mechanicId];
    }

    const tokens = [];
    for (const id of mechanicIds) {
      const userDoc = await admin.firestore().collection('users').doc(id).get();
      if (!userDoc.exists) continue;
      if (userDoc.data().isActive !== true) continue;
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
