// Use the v1 compat import since the code relies on the classic
// firebase-functions API (e.g. functions.firestore.document()).
const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const stripe = require('stripe')('sklive_KEYREPLACE');
const stripeClientId = 'ca_clientidKEYREPLACE';
const endpointSecret = 'whsec_KEYREPLACE';
const YOUR_FRONTEND_REDIRECT_URL = 'https://skiptow.site/connected';  // Replace ASAP ! with whatever redirect needed after stripe onboarding

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

exports.autoCancelStaleInvoices = functions.pubsub
  .schedule('every 24 hours')
  .timeZone('Etc/UTC')
  .onRun(async () => {
    const db = admin.firestore();
    const sixWeeksMs = 1000 * 60 * 60 * 24 * 7 * 6;
    const cutoff = new Date(Date.now() - sixWeeksMs);

    const snapshot = await db
      .collection('invoices')
      .where('invoiceStatus', '==', 'pending')
      .where('createdAt', '<', cutoff)
      .get();

    const updates = [];
    snapshot.forEach(doc => {
      updates.push(
        doc.ref.update({
          invoiceStatus: 'cancelled',
          status: 'cancelled',
          adminOverride: true,
          cancellationReason: 'Auto-cancelled after 6 weeks of inactivity.'
        })
      );
    });

    await Promise.all(updates);
    return null;
  });

exports.autoResetInactiveMechanics = functions.pubsub
  .schedule('every 24 hours')
  .timeZone('Etc/UTC')
  .onRun(async () => {
    const db = admin.firestore();
    const weekMs = 1000 * 60 * 60 * 24 * 7;
    const cutoff = new Date(Date.now() - weekMs);

    const snapshot = await db
      .collection('users')
      .where('role', '==', 'mechanic')
      .where('isActive', '==', true)
      .where('lastActiveAt', '<', cutoff)
      .get();

    const updates = [];
    snapshot.forEach(doc => {
      updates.push(doc.ref.update({ isActive: false }));
      updates.push(
        db
          .collection('notifications_mechanics')
          .doc(doc.id)
          .collection('notifications')
          .add({
            title: 'Status Auto-Reset',
            message: 'Your status was auto-reset due to inactivity.',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
          })
      );
    });

    await Promise.all(updates);
    return null;
  });

exports.createPaymentIntent = functions.https
  .onCall(async (data, context) => {
    const { amount, currency, mechanicStripeAccountId, description } = data;

    // Calculate app fee (e.g. 10% fee)
    const appFeeAmount = Math.round(amount * 0.10);  // 10% platform fee

    try {
      const paymentIntent = await stripe.paymentIntents.create({
        amount, // In cents
        currency,
        description: description || 'SkipTow Service Payment',

        // Connect payment to mechanic’s Stripe account
        transfer_data: {
          destination: mechanicStripeAccountId,
        },

        // App fee for SkipTow
        application_fee_amount: appFeeAmount,
      });

      return { clientSecret: paymentIntent.client_secret };

    } catch (error) {
      console.error('Error creating PaymentIntent:', error);
      throw new functions.https.HttpsError('unknown', 'PaymentIntent creation failed');
    }
  });

exports.generateStripeOnboardingLink = functions.https
  .onCall(async (data, context) => {
    const { userId } = data;

    const account = await stripe.accounts.create({
      type: 'standard',
    });

    const link = await stripe.accountLinks.create({
      account: account.id,
      refresh_url: YOUR_FRONTEND_REDIRECT_URL,
      return_url: YOUR_FRONTEND_REDIRECT_URL,
      type: 'account_onboarding',
    });

    await admin.firestore().collection('users').doc(userId).update({
      stripeAccountId: account.id,
    });

    return { url: link.url };
  });

exports.createStripeCheckout = functions.https
  .onCall(async (data, context) => {
    const { invoiceId, userId } = data;
    if (!invoiceId || !userId) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing invoiceId or userId');
    }

    const db = admin.firestore();
    const invoiceSnap = await db.collection('invoices').doc(invoiceId).get();
    if (!invoiceSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Invoice not found');
    }
    const invoice = invoiceSnap.data();
    const amount = Math.round(((invoice.finalPrice || invoice.estimatedPrice || 0) * 100));

    const userSnap = await db.collection('users').doc(userId).get();
    const email = userSnap.exists ? userSnap.data().email : undefined;

    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      payment_method_types: ['card'],
      customer_email: email,
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: { name: `Invoice #${invoice.invoiceNumber || invoiceId}` },
          unit_amount: amount,
        },
        quantity: 1,
      }],
      success_url: 'https://skiptow.site/success',
      cancel_url: 'https://skiptow.site/cancel',
      metadata: { invoiceId, firebaseUID: userId },
    });

    return { url: session.url };
  });
exports.createProSubscriptionSession = functions.https
  .onCall(async (data, context) => {
    try {
      const uid = context.auth?.uid;
      if (!uid) throw new functions.https.HttpsError('unauthenticated', 'You must be logged in.');

      const userDoc = await admin.firestore().collection('users').doc(uid).get();
      if (!userDoc.exists) throw new functions.https.HttpsError('not-found', 'User not found.');

      const user = userDoc.data();
      const email = user.email;
      if (!email) throw new functions.https.HttpsError('invalid-argument', 'Email is missing.');

      const stripe = require('stripe')('sklive_KEYREPLACE');

      // Create or retrieve Stripe customer
      const customerList = await stripe.customers.list({ email, limit: 1 });
      const customer = customerList.data.length > 0
        ? customerList.data[0]
        : await stripe.customers.create({
            email,
            metadata: { firebaseUID: uid, role: user.role || 'unknown' },
          });

      const session = await stripe.checkout.sessions.create({
        mode: 'subscription',
        payment_method_types: ['card'],
        customer: customer.id,
        line_items: [{
          price: 'price_KEYREPLACE',
          quantity: 1,
        }],
        success_url: 'https://skiptow.site/success?session_id={CHECKOUT_SESSION_ID}',
        cancel_url: 'https://skiptow.site/cancel',
        metadata: {
          firebaseUID: uid,
          userRole: user.role || 'unknown',
        },
      });

      await admin.firestore().collection('users').doc(uid).update({
        subscriptionStatus: 'pending',
        subscriptionRole: user.role || 'unknown',
        stripeCustomerId: customer.id,
      });

      return { sessionId: session.id, url: session.url }; //url instead of just id
    } catch (err) {
      console.error('Stripe session creation failed:', err);
      throw new functions.https.HttpsError('internal', 'Failed to create Stripe session');
    }
  });

exports.handleStripeWebhook = functions.https.onRequest({rawBody:true}, async (req, res) => {
  const sig = req.headers['stripe-signature'];
  const endpointSecret = 'whsec_KEYREPLACE';
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret);
  } catch (err) {
    console.error('Webhook signature verification failed:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  if (event.type === 'checkout.session.completed') {
    const session = event.data.object;
    const uid = session.metadata?.firebaseUID;
    const invoiceId = session.metadata?.invoiceId;
    console.log('Payment Received:',session.id);
    if (invoiceId) {
      await admin.firestore().collection('invoices').doc(invoiceId).update({
        paymentStatus: 'paid'
      }).catch(err => {
        console.error('Error updating invoice after checkout:', err);
      });
    }
    if (uid) {
      const update = {
        isPro: true,
        subscriptionStatus: 'active',
        subscriptionRole: session.metadata?.userRole || 'unknown',
      };
      if (session.subscription) {
        update.stripeSubscriptionId = session.subscription;
      }
      await admin.firestore().collection('users').doc(uid).update(update).catch(err => {
        console.error('Error updating user after checkout:', err);
      });
    }
  }

  res.json({ received: true });
});

exports.cancelProSubscription = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in.');
  }

  // Get user document
  const userDoc = await admin.firestore().collection('users').doc(uid).get();
  const userData = userDoc.data();
  const subscriptionId = userData?.stripeSubscriptionId;

  if (!subscriptionId) {
    throw new functions.https.HttpsError('not-found', 'No active Stripe subscription found.');
  }

  try {
    // Cancel subscription at period end (user stays Pro until billing cycle ends)
    await stripe.subscriptions.update(subscriptionId, {
      cancel_at_period_end: true
    });

    // Optionally: fetch subscription to get exact end date
    const updatedSub = await stripe.subscriptions.retrieve(subscriptionId);

    // Update Firestore
    await admin.firestore().collection('users').doc(uid).update({
      isPro: false,
      subscriptionStatus: 'cancelled',
      stripeSubscriptionStatus: updatedSub.status,
      subscriptionCancelAt: updatedSub.cancel_at * 1000 || null, // timestamp in ms
    });

    return {
      success: true,
      cancelledAt: updatedSub.cancel_at,
      currentPeriodEnd: updatedSub.current_period_end,
      stripeStatus: updatedSub.status
    };
  } catch (error) {
    console.error('Stripe cancellation failed:', error);
    throw new functions.https.HttpsError('internal', 'Failed to cancel subscription.');
  }
});

