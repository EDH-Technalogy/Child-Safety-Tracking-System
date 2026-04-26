const crypto = require("crypto");

const LOCAL_ADMIN_PREFIX = "local-admin-";

function normalizeEmail(email) {
  return email?.toString().trim().toLowerCase() || "";
}

function createLocalAdminId(email) {
  const digest = crypto.createHash("sha256").update(email).digest("hex");
  return `${LOCAL_ADMIN_PREFIX}${digest.slice(0, 16)}`;
}

function parseConfiguredAdmins() {
  if (!process.env.AUTH_FALLBACK_ADMINS_JSON) {
    return [];
  }

  try {
    const parsed = JSON.parse(process.env.AUTH_FALLBACK_ADMINS_JSON);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.warn("[local-auth-fallback.config] invalid AUTH_FALLBACK_ADMINS_JSON", {
      reason: error.message,
    });
    return [];
  }
}

function getFallbackAdmins() {
  const configuredAdmins = parseConfiguredAdmins();
  const includeDevDefaults =
    process.env.DISABLE_LOCAL_AUTH_FALLBACK !== "true" &&
    process.env.NODE_ENV !== "production";

  const devAdmins = includeDevDefaults
    ? [
        {
          email: "wahaj@gmail.com",
          password: "wahaj123",
          name: "Admin",
        },
        {
          email: "admin@childtracker.com",
          password: "admin123",
          name: "Admin",
        },
      ]
    : [];

  return [...configuredAdmins, ...devAdmins]
    .map((admin) => {
      const email = normalizeEmail(admin.email);
      if (!email || !admin.password) {
        return null;
      }

      return {
        id: admin.id?.toString().trim() || createLocalAdminId(email),
        name: admin.name?.toString().trim() || "Admin",
        email,
        phone: admin.phone?.toString().trim() || "",
        photo: admin.photo?.toString().trim() || "",
        role: "admin",
        status: admin.status?.toString().trim() || "active",
        password: admin.password.toString(),
        created_at: Number(admin.created_at) || Date.now(),
        source: "local_auth_fallback",
      };
    })
    .filter(Boolean);
}

function findFallbackAdminByCredentials(email, password) {
  const normalizedEmail = normalizeEmail(email);
  const normalizedPassword = password?.toString() || "";

  return (
    getFallbackAdmins().find(
      (admin) =>
        admin.email === normalizedEmail &&
        admin.password === normalizedPassword &&
        admin.status === "active"
    ) || null
  );
}

function findFallbackAdminById(adminId) {
  const normalizedId = adminId?.toString().trim() || "";
  if (!normalizedId.startsWith(LOCAL_ADMIN_PREFIX)) {
    return null;
  }

  return getFallbackAdmins().find((admin) => admin.id === normalizedId) || null;
}

function isFirestoreQuotaError(error) {
  const message = error?.message?.toString() || String(error || "");
  return (
    message.includes("RESOURCE_EXHAUSTED") ||
    message.toLowerCase().includes("quota exceeded")
  );
}

function toSafeAdmin(admin) {
  if (!admin) {
    return null;
  }

  const { password, ...safeAdmin } = admin;
  return safeAdmin;
}

module.exports = {
  LOCAL_ADMIN_PREFIX,
  findFallbackAdminByCredentials,
  findFallbackAdminById,
  isFirestoreQuotaError,
  toSafeAdmin,
};
