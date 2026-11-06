const crypto = require("crypto");
const nodemailer = require("nodemailer");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");

initializeApp();
const db = getFirestore();
const adminAuth = getAuth();

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
    html: `
      <div style="font-family:-apple-system,'Segoe UI',Roboto,sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;background:#0d1220;color:#eef2ff;">
        <div style="font-size:20px;font-weight:700;color:#7ea6ff;letter-spacing:0.5px;">ClaudVault</div>
        <h2 style="margin:16px 0 8px;font-size:18px;color:#ffffff;">Код подтверждения</h2>
        <p style="color:#aab3d0;font-size:14px;line-height:1.5;margin:0 0 8px;">Введите этот код в приложении для подтверждения действия:</p>
        <div style="margin:24px 0;padding:18px;text-align:center;background:#131a2e;border:1px solid #26314f;">
          <span style="font-size:32px;font-weight:700;letter-spacing:8px;color:#ffffff;">${escapeHtml(code)}</span>
        </div>
        <p style="color:#6b7699;font-size:12px;line-height:1.5;margin:0;">Код действует 10 минут.<br>Если вы не запрашивали код — просто проигнорируйте письмо.</p>
      </div>
    `,
  });
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function sendResetEmail(to, code, resetLink) {
  const transporter = nodemailer.createTransport({
    host: smtpHost.value(),
    port: Number(smtpPort.value()),
    secure: Number(smtpPort.value()) === 465,
    auth: { user: smtpUser.value(), pass: smtpPass.value() },
  });

  const safeLink = escapeHtml(resetLink);
  const button = resetLink
    ? `<p style="margin:24px 0;">
         <a href="${safeLink}" style="display:inline-block;background:#0A84FF;color:#ffffff;text-decoration:none;font-weight:600;font-size:15px;padding:12px 28px;border-radius:12px;">Сбросить пароль</a>
       </p>
       <p style="color:#888;font-size:12px;">Или введите код в приложении ClaudVault:</p>`
    : `<p style="color:#888;font-size:12px;">Введите код в приложении ClaudVault:</p>`;

  await transporter.sendMail({
    from: `"ClaudVault" <${smtpUser.value()}>`,
    to,
    subject: "ClaudVault — сброс пароля",
    text: [
      "Сброс пароля ClaudVault",
      "",
      resetLink ? `Сбросить пароль: ${resetLink}` : "",
      "",
      "Код для сброса в приложении:",
      "",
      `    ${code}`,
      "",
      "Код и ссылка действуют 10 минут. Если вы не запрашивали сброс пароля — проигнорируйте письмо.",
    ].filter((line) => line !== undefined).join("\n"),
    html: `
      <div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#222;">
        <h2 style="margin:0 0 8px;">Сброс пароля ClaudVault</h2>
        <p>Вы запросили сброс пароля. Нажмите кнопку ниже, чтобы задать новый пароль:</p>
        ${button}
        <p style="font-size:18px;font-weight:700;letter-spacing:4px;margin:16px 0;">${escapeHtml(code)}</p>
        <p style="color:#888;font-size:12px;">Код и ссылка действуют 10 минут.<br>Если вы не запрашивали сброс пароля — проигнорируйте письмо.</p>
      </div>
    `,
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
    const code = crypto.randomInt(0, 1000000).toString().padStart(6, "0");

    // Транзакция: проверка resend-интервала и запись кода атомарны,
    // параллельные запросы не смогут выпустить два действующих кода.
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
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

      tx.set(ref, {
        email,
        codeHash: hashCode(code),
        expiresAt: now + OTP_TTL_MS,
        attempts: 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
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

  // Вся проверка и инкремент attempts выполняются в одной транзакции:
  // параллельные запросы сериализуются и не могут «перепрыгнуть» лимит.
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError(
        "not-found",
        "Код не запрашивался. Отправьте код повторно."
      );
    }

    const data = snap.data();
    const now = Date.now();

    if ((data.expiresAt ?? 0) < now) {
      tx.delete(ref);
      throw new HttpsError("deadline-exceeded", "Срок действия кода истёк.");
    }

    if (hashCode(code) !== data.codeHash) {
      const attempts = (data.attempts ?? 0) + 1;
      if (attempts >= MAX_ATTEMPTS) {
        tx.delete(ref);
      } else {
        tx.set(ref, { attempts }, { merge: true });
      }
      throw new HttpsError("permission-denied", "Неверный код.");
    }

    // Код одноразовый — удаляем внутри той же транзакции.
    tx.delete(ref);
  });

  const validUntil = Date.now() + VERIFY_WINDOW_MS;
  await verificationRef(uid).set({
    verifiedUntil: validUntil,
    verifiedAt: FieldValue.serverTimestamp(),
  });

  return { verified: true, validUntil };
});

// ---------------------------------------------------------------------------
// QR-перенос подключений между устройствами
// ---------------------------------------------------------------------------

const QR_SESSION_COLLECTION = "qr_verification_sessions";
const QR_PUBLIC_KEY_B64_RE = /^[A-Za-z0-9+/]+={0,2}$/;

/**
 * Принимает зашифрованный пакет токенов от доверенного устройства.
 * Запись в Firestore выполняется только здесь (Admin SDK):
 * клиент не может напрямую перевести сессию в статус approved,
 * а транзакция гарантирует, что пакет принимается ровно один раз.
 */
exports.submitDeviceTransferPayload = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Требуется вход в аккаунт.");
  }
  const uid = request.auth.uid;

  const sessionID = String(request.data?.sessionID ?? "").trim();
  const trustedPublicKey = String(
    request.data?.trustedPublicKey ?? ""
  ).trim();
  const encryptedPayload = String(
    request.data?.encryptedPayload ?? ""
  ).trim();

  if (
    !/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(
      sessionID
    )
  ) {
    throw new HttpsError("invalid-argument", "Некорректный идентификатор сессии.");
  }

  const publicKeyBytes = QR_PUBLIC_KEY_B64_RE.test(trustedPublicKey)
    ? Buffer.from(trustedPublicKey, "base64")
    : null;
  if (!publicKeyBytes || publicKeyBytes.length !== 32) {
    throw new HttpsError("invalid-argument", "Некорректный ключ устройства.");
  }

  if (
    encryptedPayload.length === 0 ||
    encryptedPayload.length > 200000 ||
    !QR_PUBLIC_KEY_B64_RE.test(encryptedPayload)
  ) {
    throw new HttpsError("invalid-argument", "Некорректные данные пакета.");
  }

  const ref = db.collection(QR_SESSION_COLLECTION).doc(sessionID);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Сессия переноса не найдена.");
    }

    const data = snap.data();
    if (data.ownerUid !== uid) {
      throw new HttpsError(
        "permission-denied",
        "Сессия принадлежит другому аккаунту."
      );
    }
    if (data.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        "Сессия уже обработана или отменена."
      );
    }

    // Fail closed: отсутствующий/битый expiresAt считается истёкшим —
    // иначе pending-сессию можно было бы держать открытой бесконечно.
    const expiresAt = data.expiresAt?.toMillis?.() ?? 0;
    if (expiresAt <= Date.now()) {
      tx.delete(ref);
      throw new HttpsError("deadline-exceeded", "Срок действия сессии истёк.");
    }

    tx.update(ref, {
      trustedPublicKey,
      encryptedPayload,
      status: "approved",
      approvedAt: FieldValue.serverTimestamp(),
    });
  });

  return { submitted: true };
});

// ---------------------------------------------------------------------------
// Сброс пароля через Gmail (форма «Забыли пароль»)
// ---------------------------------------------------------------------------

function resetRef(email) {
  const digest = crypto
    .createHash("sha256")
    .update(email.toLowerCase())
    .digest("hex");
  return db.collection("password_resets").doc(digest);
}

/**
 * Шаг 1: запрашивает 6-значный код сброса и отправляет его
 * на email через Gmail SMTP. Не требует авторизации.
 * Не раскрывает, существует ли аккаунт с таким email.
 */
exports.requestPasswordResetCode = onCall(
  { secrets: [smtpPass] },
  async (request) => {
    const email = String(request.data?.email ?? "").trim().toLowerCase();
    if (!/^\S+@\S+\.\S+$/.test(email)) {
      throw new HttpsError("invalid-argument", "Некорректный email.");
    }

    let uid;
    try {
      uid = (await adminAuth.getUserByEmail(email)).uid;
    } catch (err) {
      // Пользователь не найден (или ошибка Admin SDK) — отвечаем
      // успехом, чтобы не раскрывать существование аккаунта.
      console.warn("Password reset: user lookup failed:", err.code || err);
      return { sent: true };
    }

    const ref = resetRef(email);
    const code = crypto.randomInt(0, 1000000).toString().padStart(6, "0");

    // Атомарная проверка resend-интервала и лимита попыток —
    // иначе параллельные запросы обходят ограничения.
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
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

      tx.set(ref, {
        uid,
        email,
        codeHash: hashCode(code),
        expiresAt: now + OTP_TTL_MS,
        attempts: 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    // Ссылка на стандартную веб-форму Firebase для смены пароля —
    // вставляется в письмо как кнопка.
    let resetLink = "";
    try {
      resetLink = await adminAuth.generatePasswordResetLink(email);
    } catch (err) {
      console.warn("generatePasswordResetLink failed:", err.code || err);
    }

    try {
      await sendResetEmail(email, code, resetLink);
    } catch (err) {
      console.error("Reset email send failed:", err);
      throw new HttpsError(
        "internal",
        "Не удалось отправить письмо. Попробуйте позже."
      );
    }

    return { sent: true };
  }
);

/**
 * Шаг 2: проверяет код и устанавливает новый пароль
 * через Firebase Admin SDK. Не требует авторизации.
 */
exports.confirmPasswordReset = onCall(async (request) => {
  const email = String(request.data?.email ?? "").trim().toLowerCase();
  const code = String(request.data?.code ?? "").trim();
  const newPassword = String(request.data?.newPassword ?? "");

  if (!/^\S+@\S+\.\S+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Некорректный email.");
  }
  if (!/^\d{6}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Код должен содержать 6 цифр.");
  }
  if (newPassword.length < 12 || newPassword.length > 128) {
    throw new HttpsError(
      "invalid-argument",
      "Пароль должен содержать от 12 до 128 символов."
    );
  }

  const ref = resetRef(email);

  // Атомарная проверка кода: параллельные запросы не смогут
  // «перепрыгнуть» счётчик попыток и код используется ровно один раз.
  const uid = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError(
        "not-found",
        "Код не запрашивался. Отправьте код повторно."
      );
    }

    const data = snap.data();
    const now = Date.now();

    if ((data.expiresAt ?? 0) < now) {
      tx.delete(ref);
      throw new HttpsError("deadline-exceeded", "Срок действия кода истёк.");
    }

    if (hashCode(code) !== data.codeHash) {
      const attempts = (data.attempts ?? 0) + 1;
      if (attempts >= MAX_ATTEMPTS) {
        tx.delete(ref);
      } else {
        tx.set(ref, { attempts }, { merge: true });
      }
      throw new HttpsError("permission-denied", "Неверный код.");
    }

    tx.delete(ref);
    return data.uid;
  });

  try {
    await adminAuth.updateUser(uid, { password: newPassword });
    // Смена пароля должна инвалидировать все существующие сессии.
    await adminAuth.revokeRefreshTokens(uid);
  } catch (err) {
    console.error("Password update failed:", err);
    throw new HttpsError(
      "internal",
      "Не удалось обновить пароль. Попробуйте позже."
    );
  }

  return { reset: true };
});

// ---------------------------------------------------------------------------
// Алиас send2FACode — та же логика, что и requestEmailOtp.
// iOS-клиент вызывает "requestEmailOtp"/"verifyEmailOtp"; имя send2FACode
// оставлено для соответствия спецификации и возможных внешних вызовов.
// ---------------------------------------------------------------------------
exports.send2FACode = exports.requestEmailOtp;
