const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onValueCreated } = require("firebase-functions/v2/database");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * Triggered when a new chat message is created in the Realtime Database.
 * Sends a HIGH-PRIORITY push notification to the receiver so it arrives
 * instantly even when the app is closed / killed.
 */
exports.onChatMessage = onValueCreated("/chats/{chatId}/messages/{messageId}", async (event) => {
    const message = event.data.val();
    const chatId = event.params.chatId; // e.g., "uid1_uid2"

    // Ignore AI messages or invalid chat IDs
    if (chatId.startsWith("ai_") || message.senderId === "vanguard_ai") {
        return;
    }

    const senderId = message.senderId;
    const uids = chatId.split("_");

    // The receiver is the UID that is NOT the sender
    const receiverId = uids.find(id => id !== senderId);
    if (!receiverId) return;

    // Fetch receiver's FCM token from Firestore
    const userDoc = await db.collection("users").doc(receiverId).get();
    if (!userDoc.exists) return;

    const token = userDoc.data().fcmToken;
    if (!token) {
        console.log(`No FCM token for user ${receiverId}`);
        return;
    }

    let textPreview = message.text || "";
    if (message.imageUrl) textPreview = "📷 Sent a photo";

    // ── HIGH PRIORITY payload — wakes Android even when app is killed ──
    const payload = {
        token: token,
        notification: {
            title: message.senderName || "New Message",
            body: textPreview,
        },
        data: {
            chatId: chatId,
            type: "chat_message",
        },
        android: {
            priority: "high",           // FCM transport priority — HIGH wakes the device
            notification: {
                channel_id: "vanguard_alerts", // must match channel created in Flutter
                priority: "max",               // shows as heads-up (pops on screen)
                default_sound: true,
                default_vibrate_timings: true,
                notification_count: 1,
            },
            ttl: "60s",                 // discard if undelivered after 60 seconds
        },
        apns: {
            headers: { "apns-priority": "10" }, // iOS immediate delivery
            payload: {
                aps: {
                    sound: "default",
                    badge: 1,
                    "content-available": 1,     // wakes iOS in background
                },
            },
        },
    };

    try {
        await admin.messaging().send(payload);
        console.log(`✅ Chat notification sent to ${receiverId}`);
    } catch (error) {
        console.error("Error sending chat notification:", error);
        // Auto-clean stale/invalid token so future sends don't waste time
        if (error.code === "messaging/registration-token-not-registered") {
            await db.collection("users").doc(receiverId).update({
                fcmToken: admin.firestore.FieldValue.delete(),
            });
            console.log(`🗑️ Stale token removed for ${receiverId}`);
        }
    }
});

/**
 * Triggered when a new alert document is created in Firestore.
 * Sends an emergency HIGH-PRIORITY push notification to all contacts of the sender.
 */
exports.onEmergencyAlert = onDocumentCreated("alerts/{alertId}", async (event) => {
    const alertData = event.data.data();
    const senderId = alertData.senderId;
    const senderName = alertData.senderName || "Someone";
    const alertType = alertData.alertType || "EMERGENCY";

    if (!senderId) return;

    // 1. Fetch sender's emergency contacts
    const contactsSnapshot = await db.collection("users").doc(senderId).collection("contacts").get();

    if (contactsSnapshot.empty) {
        console.log(`User ${senderId} has no emergency contacts.`);
        return;
    }

    const fcmTokens = [];

    // 2. Resolve each contact's UID and collect their FCM token
    for (const doc of contactsSnapshot.docs) {
        const contactInfo = doc.data().contact;
        try {
            let userRecord;
            if (contactInfo.includes("@")) {
                userRecord = await admin.auth().getUserByEmail(contactInfo);
            } else {
                userRecord = await admin.auth().getUserByPhoneNumber(contactInfo);
            }

            if (userRecord && userRecord.uid) {
                const targetDoc = await db.collection("users").doc(userRecord.uid).get();
                if (targetDoc.exists && targetDoc.data().fcmToken) {
                    fcmTokens.push(targetDoc.data().fcmToken);
                }
            }
        } catch (authError) {
            console.error(`Could not find contact ${contactInfo}:`, authError.message);
        }
    }

    // 3. Send multicast HIGH-PRIORITY emergency notification
    if (fcmTokens.length > 0) {
        const multicastPayload = {
            notification: {
                title: `🚨 ${alertType} ALERT from ${senderName}`,
                body: `${senderName} needs help! Check their location immediately.`,
            },
            data: {
                alertId: event.params.alertId,
                type: "emergency_alert",
                senderId: senderId,
            },
            android: {
                priority: "high",
                notification: {
                    channel_id: "vanguard_alerts",
                    priority: "max",
                    default_sound: true,
                    default_vibrate_timings: true,
                    notification_count: 1,
                },
                ttl: "60s",
            },
            apns: {
                headers: { "apns-priority": "10" },
                payload: {
                    aps: {
                        sound: "default",
                        badge: 1,
                        "content-available": 1,
                    },
                },
            },
            tokens: fcmTokens,
        };

        try {
            const response = await admin.messaging().sendEachForMulticast(multicastPayload);
            console.log(`✅ Alert sent to ${response.successCount}/${fcmTokens.length} contacts`);
        } catch (error) {
            console.error("Error sending emergency alert multicast:", error);
        }
    } else {
        console.log("No valid FCM tokens found for the emergency contacts.");
    }
});
