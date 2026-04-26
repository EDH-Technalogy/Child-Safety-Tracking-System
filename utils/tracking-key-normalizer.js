function safeDecodeURIComponent(value) {
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return value;
  }
}

function extractTrackingKeyCandidate(input) {
  const raw = input?.toString().trim() || "";
  if (!raw) {
    return "";
  }

  const decoded = safeDecodeURIComponent(raw).replace(/~2F/gi, "/");
  const candidates = [raw, decoded, safeDecodeURIComponent(decoded)];

  for (const candidate of candidates) {
    const match = candidate.match(
      /(?:^|\/)live_tracking\/([^/?#]+)(?:\/(?:location|status))?/i
    );
    if (match?.[1]) {
      return match[1].trim();
    }
  }

  return decoded;
}

function normalizeTrackingKey(input) {
  const raw = input?.toString().trim() || "";
  if (!raw) {
    throw new Error("trackingKey is required");
  }

  const candidate = extractTrackingKeyCandidate(raw).trim();
  if (!candidate) {
    throw new Error("trackingKey is required");
  }

  if (/^https?:\/\//i.test(candidate)) {
    throw new Error("trackingKey must not be a Firebase Console URL");
  }

  if (candidate.includes("/")) {
    throw new Error("trackingKey must not contain path separators");
  }

  if (!/^[A-Za-z0-9._:-]+$/.test(candidate)) {
    throw new Error("trackingKey contains invalid characters");
  }

  return candidate;
}

function tryNormalizeTrackingKey(input) {
  try {
    return normalizeTrackingKey(input);
  } catch (_) {
    return "";
  }
}

module.exports = {
  normalizeTrackingKey,
  tryNormalizeTrackingKey,
};
