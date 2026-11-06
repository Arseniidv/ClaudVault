const crypto = require("crypto");
const nodemailer = require("nodemailer");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");

initializeApp();
const db = getFirestore();

// Конфигурация SMTP (Gmail: используйте App Password, не основной пароль).
// Задайте через:
//   firebase functions:secrets:set SMTP_PASS
//   gcloud functions deploy ... --set-env-vars или .env в functions/:
//     SMTP_HOST=smtp.gmail.com
//     SMTP_PORT=465
//     SMTP_USER=your.address@gmail.com
const smtpHost = defineString("SMTP_HOST", { default: "smtp.gmail.com" });
const smtpPort = defineString("SMTP_PORT", { default: "465" });
const smtpUser = defineString("SMTP_USER");
const smtpPass = defineSecret("SMTP_PASS");

const OTP_TTL_MS = 10 * 60 * 1000;          // код живёт 10 минут
const VERIFY_WINDOW_MS = 15 * 60 * 1000;    // после ввода кода — 15 минут "доверенного" окна
const RESEND_INTERVAL_MS = 60 * 1000;       // не чаще 1 кода в минуту
const MAX_ATTEMPTS = 5;

function otpRef(uid) {
  return db.collection("otps").doc(uid);
}

function verificationRef(uid) {
  return db.collection("verifications").doc(uid);
}

function hashCode(code) {
  return crypto.createHash("sha256").update(code).digest("hex");
}

async function sendOtpEmail(to, code) {
  const transporter = nodemailer.createTransport({
    host: smtpHost.value(),
    port: Number(smtpPort.value()),
    secure: Number(smtpPort.value()) === 465,
    auth: { user: smtpUser.value(), pass: smtpPass.value() },
  });

  await transporter.sendMail({
    from: `"ClaudVault" <${smtpUser.value()}>`,
    to,
    subject: "ClaudVault — код подтверждения",
    text: [
      "Ваш код подтверждения ClaudVault:",
      "",
      `    ${code}`,
      "",
      "Код действует 10 минут. Если вы не запрашивали код — проигнорируйте письмо.",
    ].join("\n"),
  });
}

/**
 * Запрашивает 6-значный OTP-код и отправляет его на email авторизованного
 * пользователя. Email берётся из Firebase Auth token — клиент не может
 * подменить адрес.
 */
exports.requestEmailOtp = onCall(
  { secrets: [smtpPass] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Требуется вход в аккаунт.");
    }
    const uid = request.auth.uid;
    const email = request.auth.token.email;
    if (!email) {
      throw new HttpsError(
        "failed-precondition",
        "У аккаунта нет email."
      );
    }

    const ref = otpRef(uid);
    const existing = await ref.get();
    const now = Date.now();

    if (existing.exists) {
      const data = existing.data();
      const lastSent = data.updatedAt?.toMillis?.() ?? 0;
      if (now - lastSent < RESEND_INTERVAL_MS) {
        throw new HttpsError(
          "resource-exhausted",
          "Код уже отправлен. Повторите через минуту."
        );
      }
      if ((data.attempts ?? 0) >= MAX_ATTEMPTS &&
          (data.expiresAt ?? 0) > now) {
        throw new HttpsError(
          "resource-exhausted",
          "Слишком много попыток. Запросите новый код."
        );
      }
    }

    const code = crypto.randomInt(0, 1000000).toString().padStart(6, "0");

    await ref.set({
      email,
      codeHash: hashCode(code),
      expiresAt: now + OTP_TTL_MS,
      attempts: 0,
      updatedAt: FieldValue.serverTimestamp(),
    });

    try {
      await sendOtpEmail(email, code);
    } catch (err) {
      console.error("OTP email send failed:", err);
      throw new HttpsError(
        "internal",
        "Не удалось отправить письмо. Попробуйте позже."
      );
    }

    return { sent: true };
  }
);

/**
 * Проверяет введённый код. При успехе открывает "доверенное окно"
 * на VERIFY_WINDOW_MS и возвращает его срок действия.
 */
exports.verifyEmailOtp = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Требуется вход в аккаунт.");
  }
  const uid = request.auth.uid;
  const code = String(request.data?.code ?? "").trim();

  if (!/^\d{6}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Код должен содержать 6 цифр.");
  }

  const ref = otpRef(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError(
      "not-found",
      "Код не запрашивался. Отправьте код повторно."
    );
  }

  const data = snap.data();
  const now = Date.now();

  if ((data.expiresAt ?? 0) < now) {
    await ref.delete();
    throw new HttpsError("deadline-exceeded", "Срок действия кода истёк.");
  }

  if (hashCode(code) !== data.codeHash) {
    const attempts = (data.attempts ?? 0) + 1;
    await ref.set({ attempts }, { merge: true });
    if (attempts >= MAX_ATTEMPTS) {
      await ref.delete();
    }
    throw new HttpsError("permission-denied", "Неверный код.");
  }

  await ref.delete();
  const validUntil = now + VERIFY_WINDOW_MS;
  await verificationRef(uid).set({
    verifiedUntil: validUntil,
    verifiedAt: FieldValue.serverTimestamp(),
  });

  return { verified: true, validUntil };
});
