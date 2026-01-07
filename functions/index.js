const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

// Configure your email transporter
// IMPORTANT: For Gmail, you MUST use an 'App Password', not your login password.
// Steps: Google Account -> Security -> 2-Step Verification -> App Passwords
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: "unitedkingdom1799@gmail.com",
    pass: "eezu wcqd evsv kolc",
  },
});

exports.sendOtp = functions.region('asia-south1').https.onCall(async (data, context) => {
  const email = data.email;
  if (!email) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "The function must be called with an email."
    );
  }

  // Generate 4-digit code
  const otp = Math.floor(1000 + Math.random() * 9000).toString();

  // Expiration (e.g., 10 minutes from now)
  const expiresAt = Date.now() + 10 * 60 * 1000;

  try {
    // Store in Firestore: otp_codes/{email}
    // We use email as ID for simplicity (ensure email is lowercased/sanitized in production)
    await admin.firestore().collection("otp_codes").doc(email).set({
      otp: otp,
      expiresAt: expiresAt,
    });

    // Send Email
    const mailOptions = {
      from: "Your App Name <noreply@yourapp.com>",
      to: email,
      subject: "Your Password Reset Code",
      text: `Your Verification Code is: ${otp}`,
      html: `<p>Your Verification Code is: <strong>${otp}</strong></p><p>This code expires in 10 minutes.</p>`,
    };

    await transporter.sendMail(mailOptions);

    return { success: true, message: "OTP sent successfully" };
  } catch (error) {
    console.error("Error sending OTP:", error);
    throw new functions.https.HttpsError("internal", "Unable to send OTP.");
  }
});

exports.resetPasswordWithOtp = functions.region('asia-south1').https.onCall(async (data, context) => {
  const email = data.email;
  const otp = data.otp;
  const newPassword = data.newPassword;

  if (!email || !otp || !newPassword) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Email, OTP, and New Password are required."
    );
  }

  try {
    // 1. Verify OTP from Firestore
    const doc = await admin.firestore().collection("otp_codes").doc(email).get();

    if (!doc.exists) {
      throw new functions.https.HttpsError("not-found", "Invalid OTP request.");
    }

    const savedData = doc.data();
    const now = Date.now();

    if (savedData.otp !== otp) {
      throw new functions.https.HttpsError("permission-denied", "Invalid OTP code.");
    }

    if (now > savedData.expiresAt) {
      throw new functions.https.HttpsError("permission-denied", "OTP has expired.");
    }

    // 2. Reset Password using Admin SDK
    const userRecord = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(userRecord.uid, {
      password: newPassword,
    });

    // 3. Delete used OTP
    await admin.firestore().collection("otp_codes").doc(email).delete();

    return { success: true, message: "Password updated successfully" };
  } catch (error) {
    console.error("Error resetting password:", error);
    // Pass through specific errors, mask others
    if (error.code && error.code.startsWith("functions/")) {
      throw error;
    }
    throw new functions.https.HttpsError("internal", "Unable to reset password.");
  }
});
