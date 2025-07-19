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
    if (!mechanicId || !customerId) return null;

    const customerSnap = await admin.firestore()
      .collection('users')
      .doc(customerId)
      .get();
    const customerUsername = customerSnap.exists && customerSnap.data().username
      ? customerSnap.data().username
      : 'customer';

    let mechanicIds = [];
    if (mechanicId === 'any') {
      // Notify all nearby active mechanics
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

    const message = {
      notification: {
        title: 'New Service Request',
        body: `You\u2019ve received a new service request from ${customerUsername}.`
      },
      tokens
    };

    await admin.messaging().sendEachForMulticast(message);
    return null;
  });
