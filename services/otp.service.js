const bcrypt = require("bcrypt");
const crypto = require("crypto");
const { admin, auth, db } = require("../firebase");
const { createAuthToken } = require("../utils/auth-token");
const { generateOTP } = require("../utils/otp");
const {
  createHttpError,
  validateGmailEmail,
  validateStrongPassword,
} = require("../utils/auth-validation");
const { sendOtpEmail, sendPasswordResetLink } = require("./email.service");

const OTP_COLLECTION = "otp_codes";
const USERS_COLLECTION = "users";
const OTP_TTL_MS = 5 * 60 * 1000;
const OTP_COOLDOWN_MS = 30 * 1000;
const OTP_MAX_ATTEMPTS = 5;
const VALID_OTP_TYPES = new Set(["signup", "forgot"]);

function normalizeOtpType(type) {
  const normalizedType = type?.toString().trim().toLowerCase() || "";
  if (!VALID_OTP_TYPES.has(normalizedType)) {
    throw createHttpError(400, "Invalid OTP type");
  }
  return normalizedType;
}

function otpDocId(email, type) {
  return crypto
    .createHash("sha256")
    .update(`${type}:${email}`)
    .digest("hex");
}

function userResponse(userId, userData = {}) {
  const fullName = userData.fullName || userData.name || "";

  return {
    id: userId,
    fullName,
    name: fullName,
    phone: userData.phone || "",
    email: userData.email || "",
    photo: userData.photo || "",
    role: userData.role || "user",
    status: userData.status || "active",
    created_at: userData.created_at || Date.now(),
  };
}

async function findUserDocumentByEmail(email) {
  const snapshot = await db
    .collection(USERS_COLLECTION)
    .where("email", "==", email)
    .limit(1)
    .get();

  return snapshot.empty ? null : snapshot.docs[0];
}

async function getFirebaseUserByEmail(email) {
  try {
    return await auth.getUserByEmail(email);
  } catch (error) {
    if (error.code === "auth/user-not-found") {
      return null;
    }
    throw error;
  }
}

async function createOrUpdatePendingSignup({
  email,
  fullName,
  password,
  source,
}) {
  const existingUserDoc = await findUserDocumentByEmail(email);
  const existingUserData = existingUserDoc?.data() || null;

  if (existingUserData && existingUserData.isVerified !== false) {
    throw createHttpError(400, "Email already registered");
  }

  const existingFirebaseUser = await getFirebaseUserByEmail(email);
  if (existingFirebaseUser && !existingFirebaseUser.disabled) {
    throw createHttpError(400, "Email already registered");
  }

  const firebaseUser = existingFirebaseUser
    ? await auth.updateUser(existingFirebaseUser.uid, {
        displayName: fullName,
        password,
        emailVerified: false,
        disabled: true,
      })
    : await auth.createUser({
        email,
        password,
        displayName: fullName,
        emailVerified: false,
        disabled: true,
      });

  const hashedPassword = await bcrypt.hash(password, 10);
  const now = Date.now();
  const userRef =
    existingUserDoc?.ref || db.collection(USERS_COLLECTION).doc(firebaseUser.uid);

  await userRef.set(
    {
      fullName,
      name: fullName,
      email,
      phone: existingUserData?.phone || "",
      photo: existingUserData?.photo || "",
      password: hashedPassword,
      password_hash: hashedPassword,
      firebaseUid: firebaseUser.uid,
      role: existingUserData?.role || "user",
      status: existingUserData?.status || "active",
      isVerified: false,
      auth_provider: "email_password",
      created_at: existingUserData?.created_at || now,
      updated_at: now,
      signup_source: source || "otp",
    },
    { merge: true }
  );

  return {
    firebaseUid: firebaseUser.uid,
    userDocId: userRef.id,
    fullName,
  };
}

async function assertForgotPasswordAccountExists(email) {
  const [userDoc, firebaseUser] = await Promise.all([
    findUserDocumentByEmail(email),
    getFirebaseUserByEmail(email),
  ]);

  if (!userDoc && !firebaseUser) {
    throw createHttpError(404, "Email not found");
  }

  return { userDoc, firebaseUser };
}

async function sendOtp(payload = {}) {
  // Step 1: validate the OTP purpose and Gmail address before doing any work.
  const type = normalizeOtpType(payload.type);
  const email = validateGmailEmail(payload.email);
  const now = Date.now();
  const otpRef = db.collection(OTP_COLLECTION).doc(otpDocId(email, type));
  const existingOtpDoc = await otpRef.get();

  // Step 2: enforce the 30-second resend cooldown.
  if (existingOtpDoc.exists) {
    const existingOtp = existingOtpDoc.data() || {};
    const createdAt = Number(existingOtp.createdAt || 0);
    if (createdAt && now - createdAt < OTP_COOLDOWN_MS) {
      throw createHttpError(429, "Please wait 30 seconds before requesting another OTP");
    }
  }

  let signupContext = null;

  if (type === "signup") {
    // Step 3a: validate signup fields and create/update a disabled Firebase user.
    const fullName = (
      payload.fullName ??
      payload.name ??
      ""
    ).toString().trim();
    const password = payload.password?.toString() || "";
    const confirmPassword = (
      payload.confirmPassword ??
      payload.confirm_password ??
      ""
    ).toString();
    const existingUserDoc = await findUserDocumentByEmail(email);
    const existingUserData = existingUserDoc?.data() || null;
    const canResendPendingSignup =
      existingUserData?.isVerified === false &&
      existingUserData?.firebaseUid &&
      (!fullName || !password || !confirmPassword);

    if (canResendPendingSignup) {
      signupContext = {
        firebaseUid: existingUserData.firebaseUid,
        userDocId: existingUserDoc.id,
        fullName: existingUserData.fullName || existingUserData.name || "",
      };
    } else {
      if (!fullName || !email || !password || !confirmPassword) {
        throw createHttpError(400, "All fields are required");
      }

      validateStrongPassword(password);

      if (password !== confirmPassword) {
        throw createHttpError(400, "Passwords do not match");
      }

      signupContext = await createOrUpdatePendingSignup({
        email,
        fullName,
        password,
        source: payload.source,
      });
    }
  } else {
    // Step 3b: forgot-password OTPs are only sent for known accounts.
    await assertForgotPasswordAccountExists(email);
  }

  // Step 4: hash the OTP before writing it to Firestore.
  const otp = generateOTP();
  const hashedOtp = await bcrypt.hash(otp, 10);

  await otpRef.set({
    email,
    otp: hashedOtp,
    type,
    attempts: 0,
    createdAt: now,
    expiresAt: now + OTP_TTL_MS,
    ...(signupContext || {}),
  });

  // Step 5: send the plain OTP only over email.
  await sendOtpEmail(email, otp, type);

  return {
    success: true,
    message: "OTP sent successfully",
    email,
    type,
    cooldownSeconds: Math.floor(OTP_COOLDOWN_MS / 1000),
    expiresInSeconds: Math.floor(OTP_TTL_MS / 1000),
  };
}

async function verifyOtp(payload = {}) {
  // Step 1: validate request shape and locate the hashed OTP record.
  const type = normalizeOtpType(payload.type);
  const email = validateGmailEmail(payload.email);
  const inputOtp = payload.otp?.toString().trim() || "";

  if (!/^\d{6}$/.test(inputOtp)) {
    throw createHttpError(400, "Invalid OTP");
  }

  const otpRef = db.collection(OTP_COLLECTION).doc(otpDocId(email, type));
  const otpDoc = await otpRef.get();

  if (!otpDoc.exists) {
    throw createHttpError(400, "Invalid request");
  }

  const otpData = otpDoc.data() || {};
  const attempts = Number(otpData.attempts || 0);
  const expiresAt = Number(otpData.expiresAt || 0);

  // Step 2: reject expired OTPs and delete stale records.
  if (!expiresAt || Date.now() > expiresAt) {
    await otpRef.delete();
    throw createHttpError(400, "OTP expired");
  }

  if (attempts >= OTP_MAX_ATTEMPTS) {
    throw createHttpError(429, "Too many OTP attempts");
  }

  // Step 3: compare against the hashed OTP and count failed attempts.
  const otpMatches = await bcrypt.compare(inputOtp, otpData.otp || "");
  if (!otpMatches) {
    await otpRef.update({
      attempts: admin.firestore.FieldValue.increment(1),
      lastAttemptAt: Date.now(),
    });
    throw createHttpError(400, "Invalid OTP");
  }

  if (type === "signup") {
    // Step 4a: verified signup enables Firebase Auth and returns the existing JWT.
    return verifySignupOtp({ email, otpData, otpRef });
  }

  // Step 4b: verified forgot-password OTP resets password or sends a reset link.
  return verifyForgotPasswordOtp({ email, payload, otpRef });
}

async function verifySignupOtp({ email, otpData, otpRef }) {
  const firebaseUid = otpData.firebaseUid;
  const userDocId = otpData.userDocId || firebaseUid;

  if (!firebaseUid || !userDocId) {
    throw createHttpError(400, "Invalid request");
  }

  await auth.updateUser(firebaseUid, {
    disabled: false,
    emailVerified: true,
  });

  const userRef = db.collection(USERS_COLLECTION).doc(userDocId);
  await userRef.update({
    isVerified: true,
    otp: admin.firestore.FieldValue.delete(),
    otpExpires: admin.firestore.FieldValue.delete(),
    otpExpiry: admin.firestore.FieldValue.delete(),
    updated_at: Date.now(),
  });

  const verifiedDoc = await userRef.get();
  const verifiedUser = verifiedDoc.data() || {};
  const responseUser = userResponse(verifiedDoc.id, verifiedUser);
  const token = createAuthToken({
    subjectId: verifiedDoc.id,
    role: responseUser.role,
    subjectType: "user",
    email: responseUser.email,
  });

  await otpRef.delete();

  return {
    success: true,
    message: "Email verified successfully",
    user: responseUser,
    token,
  };
}

async function verifyForgotPasswordOtp({ email, payload, otpRef }) {
  const newPassword = payload.newPassword ?? payload.new_password;
  const userDoc = await findUserDocumentByEmail(email);
  const firebaseUser = await getFirebaseUserByEmail(email);
  let passwordResetLink = null;

  if (newPassword !== undefined && newPassword !== null && newPassword !== "") {
    validateStrongPassword(newPassword);
    const hashedPassword = await bcrypt.hash(newPassword.toString(), 10);
    let nextFirebaseUser = firebaseUser;

    if (nextFirebaseUser) {
      nextFirebaseUser = await auth.updateUser(nextFirebaseUser.uid, {
        password: newPassword.toString(),
        disabled: false,
        emailVerified: true,
      });
    } else {
      nextFirebaseUser = await auth.createUser({
        email,
        password: newPassword.toString(),
        displayName: userDoc?.data()?.fullName || userDoc?.data()?.name || "",
        emailVerified: true,
        disabled: false,
      });
    }

    if (userDoc) {
      await userDoc.ref.update({
        password: hashedPassword,
        password_hash: hashedPassword,
        firebaseUid: nextFirebaseUser.uid,
        isVerified: true,
        updated_at: Date.now(),
      });
    }
  } else {
    if (!firebaseUser) {
      throw createHttpError(404, "Firebase user not found");
    }
    passwordResetLink = await auth.generatePasswordResetLink(email);
    await sendPasswordResetLink(email, passwordResetLink);
  }

  await otpRef.delete();

  return {
    success: true,
    message: "OTP verified successfully",
    ...(passwordResetLink ? { passwordResetLink } : {}),
  };
}

module.exports = {
  OTP_COOLDOWN_MS,
  OTP_MAX_ATTEMPTS,
  OTP_TTL_MS,
  sendOtp,
  verifyOtp,
};
