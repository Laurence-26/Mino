const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");
const twilio = require("twilio");

admin.initializeApp();

const twilioSid = defineString("TWILIO_SID");
const twilioToken = defineString("TWILIO_TOKEN");
const twilioServiceSid = defineString("TWILIO_SERVICE_SID");

exports.sendOTP = onCall(async (request) => {
  const client = twilio(twilioSid.value(), twilioToken.value());
  const { phoneNumber } = request.data;

  if (!phoneNumber) {
    throw new HttpsError("invalid-argument", "Phone number is required");
  }

  try {
    await client.verify.v2
      .services(twilioServiceSid.value())
      .verifications.create({ to: phoneNumber, channel: "sms" });
    return { success: true };
  } catch (error) {
    console.error("Twilio sendOTP error:", error);
    throw new HttpsError("internal", error.message);
  }
});

exports.verifyOTP = onCall(async (request) => {
  const client = twilio(twilioSid.value(), twilioToken.value());
  const { phoneNumber, code } = request.data;

  if (!phoneNumber || !code) {
    throw new HttpsError(
      "invalid-argument",
      "Phone number and code are required"
    );
  }

  try {
    const result = await client.verify.v2
      .services(twilioServiceSid.value())
      .verificationChecks.create({ to: phoneNumber, code });
    return { success: result.status === "approved" };
  } catch (error) {
    console.error("Twilio verifyOTP error:", error);
    throw new HttpsError("internal", error.message);
  }
});

exports.onGroupTransactionCreated = onDocumentCreated(
  "groups/{groupId}/transactions/{transactionId}",
  async (event) => {
    const { groupId, transactionId } = event.params;
    const tx = event.data?.data();
    if (!tx) return;

    const senderUid = tx.userId;
    const senderName = tx.addedBy || "Someone";
    const amount = tx.amount;
    const type = tx.type;
    const category = tx.category;

    const db = admin.firestore();

    const groupSnap = await db.doc(`groups/${groupId}`).get();
    if (!groupSnap.exists) return;
    const group = groupSnap.data();
    const groupName = group.name || "your group";
    const memberUids = Object.keys(group.members || {});

    const recipientUids = memberUids.filter((uid) => uid !== senderUid);
    if (recipientUids.length === 0) return;

    const userDocs = await db.getAll(
      ...recipientUids.map((uid) => db.doc(`users/${uid}`))
    );
    const tokens = userDocs
      .map((doc) => doc.data()?.fcmToken)
      .filter(Boolean);
    if (tokens.length === 0) return;

    const verb = type === "income" ? "added income" : "added an expense";
    const formattedAmount = Number(amount).toFixed(2);

    const response = await admin.messaging().sendEachForMulticast({
      notification: {
        title: `${groupName}: New transaction`,
        body: `${senderName} ${verb} of ${formattedAmount} (${category})`,
      },
      data: {
        type: "group_transaction",
        groupId,
        transactionId,
      },
      tokens,
      android: {
        priority: "high",
        notification: { channelId: "group_transactions" },
      },
    });

    // Clean up stale tokens
    const staleTokens = [];
    response.responses.forEach((r, idx) => {
      if (
        !r.success &&
        (r.error?.code === "messaging/invalid-registration-token" ||
          r.error?.code === "messaging/registration-token-not-registered")
      ) {
        staleTokens.push({ uid: recipientUids[idx], token: tokens[idx] });
      }
    });
    await Promise.all(
      staleTokens.map(({ uid }) =>
        db.doc(`users/${uid}`).update({ fcmToken: admin.firestore.FieldValue.delete() })
      )
    );
  }
);