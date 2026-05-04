const https = require("https");
const { OAuth2Client } = require("google-auth-library");

const GOOGLE_ISSUERS = new Set([
  "accounts.google.com",
  "https://accounts.google.com",
]);
const googleClient = new OAuth2Client();

function createHttpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function normalizeSocialProvider(provider) {
  const normalized = provider?.toString().trim().toLowerCase() || "";
  if (normalized === "google" || normalized === "facebook") {
    return normalized;
  }
  return "";
}

function normalizeString(value) {
  return value?.toString().trim() || "";
}

function normalizeEmail(value) {
  return normalizeString(value).toLowerCase();
}

function readEnvList(keys) {
  const values = [];
  for (const key of keys) {
    const raw = process.env[key];
    if (!raw) {
      continue;
    }

    values.push(
      ...raw
        .split(",")
        .map((value) => value.trim())
        .filter(Boolean)
    );
  }
  return [...new Set(values)];
}

function getGoogleAudiences() {
  return readEnvList([
    "GOOGLE_CLIENT_ID",
    "GOOGLE_WEB_CLIENT_ID",
    "GOOGLE_ANDROID_CLIENT_ID",
    "GOOGLE_IOS_CLIENT_ID",
    "GOOGLE_OAUTH_CLIENT_IDS",
  ]);
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    const request = https.get(
      url,
      {
        headers: {
          Accept: "application/json",
        },
      },
      (response) => {
        let body = "";

        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          body += chunk;
          if (body.length > 1024 * 1024) {
            request.destroy(new Error("Social provider response is too large"));
          }
        });
        response.on("end", () => {
          let parsed;
          try {
            parsed = body ? JSON.parse(body) : {};
          } catch (error) {
            reject(createHttpError(502, "Invalid social provider response"));
            return;
          }

          if (response.statusCode < 200 || response.statusCode >= 300) {
            const message =
              parsed?.error?.message ||
              parsed?.error_description ||
              "Social provider rejected the token";
            reject(createHttpError(401, message));
            return;
          }

          resolve(parsed);
        });
      }
    );

    request.setTimeout(15000, () => {
      request.destroy(new Error("Social provider request timed out"));
    });
    request.on("error", reject);
  });
}

async function verifyGoogleToken(accessToken) {
  const token = normalizeString(accessToken);
  if (!token) {
    throw createHttpError(400, "Google token is required");
  }

  const audiences = getGoogleAudiences();
  let ticket;
  try {
    ticket = await googleClient.verifyIdToken({
      idToken: token,
      ...(audiences.length > 0 ? { audience: audiences } : {}),
    });
  } catch (_) {
    throw createHttpError(401, "Invalid Google token");
  }
  const payload = ticket.getPayload();

  if (!payload?.sub) {
    throw createHttpError(401, "Invalid Google token");
  }
  if (!GOOGLE_ISSUERS.has(payload.iss)) {
    throw createHttpError(401, "Invalid Google token issuer");
  }
  if (!normalizeEmail(payload.email)) {
    throw createHttpError(400, "Google account email is required");
  }
  if (payload.email_verified !== true && payload.email_verified !== "true") {
    throw createHttpError(403, "Google email is not verified");
  }

  return {
    provider: "google",
    providerId: payload.sub,
    email: normalizeEmail(payload.email),
    name: normalizeString(payload.name) || normalizeEmail(payload.email),
    photo: normalizeString(payload.picture),
  };
}

async function verifyFacebookToken(accessToken) {
  const token = normalizeString(accessToken);
  if (!token) {
    throw createHttpError(400, "Facebook token is required");
  }

  const facebookAppId = normalizeString(process.env.FACEBOOK_APP_ID);
  const facebookAppSecret = normalizeString(process.env.FACEBOOK_APP_SECRET);
  let expectedFacebookUserId = "";

  if (facebookAppId && facebookAppSecret) {
    const debugParams = new URLSearchParams({
      input_token: token,
      access_token: `${facebookAppId}|${facebookAppSecret}`,
    });
    const debugData = await getJson(
      `https://graph.facebook.com/debug_token?${debugParams.toString()}`
    );
    const tokenData = debugData?.data || {};

    if (tokenData.is_valid !== true) {
      throw createHttpError(401, "Invalid Facebook token");
    }
    if (tokenData.app_id && tokenData.app_id.toString() !== facebookAppId) {
      throw createHttpError(401, "Facebook token app mismatch");
    }
    if (
      tokenData.expires_at &&
      Number(tokenData.expires_at) * 1000 <= Date.now()
    ) {
      throw createHttpError(401, "Facebook token expired");
    }

    expectedFacebookUserId = normalizeString(tokenData.user_id);
  }

  const meParams = new URLSearchParams({
    fields: "id,name,email,picture.type(large)",
    access_token: token,
  });
  const profile = await getJson(
    `https://graph.facebook.com/me?${meParams.toString()}`
  );
  const providerId = normalizeString(profile.id);

  if (!providerId) {
    throw createHttpError(401, "Invalid Facebook token");
  }
  if (expectedFacebookUserId && expectedFacebookUserId !== providerId) {
    throw createHttpError(401, "Facebook token user mismatch");
  }

  const email = normalizeEmail(profile.email);
  if (!email) {
    throw createHttpError(400, "Facebook email permission is required");
  }

  return {
    provider: "facebook",
    providerId,
    email,
    name: normalizeString(profile.name) || email,
    photo: normalizeString(profile.picture?.data?.url),
  };
}

async function verifySocialAccessToken(provider, accessToken) {
  const normalizedProvider = normalizeSocialProvider(provider);
  if (!normalizedProvider) {
    throw createHttpError(400, "Provider must be google or facebook");
  }

  return normalizedProvider === "google"
    ? verifyGoogleToken(accessToken)
    : verifyFacebookToken(accessToken);
}

module.exports = {
  normalizeSocialProvider,
  verifySocialAccessToken,
};
