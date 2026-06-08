const DEFAULT_REVERSE_GEOCODE_TIMEOUT_MS = 5000;
const DEFAULT_REVERSE_GEOCODE_ENDPOINT =
  "https://nominatim.openstreetmap.org/reverse";

function parseCoordinate(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function buildFallbackPlaceName(latitude, longitude) {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  return `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
}

async function reverseGeocodeCoordinates(latitude, longitude) {
  const normalizedLatitude = parseCoordinate(latitude);
  const normalizedLongitude = parseCoordinate(longitude);
  if (
    normalizedLatitude === null ||
    normalizedLongitude === null ||
    typeof fetch !== "function"
  ) {
    return buildFallbackPlaceName(normalizedLatitude, normalizedLongitude);
  }

  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => {
    controller.abort();
  }, DEFAULT_REVERSE_GEOCODE_TIMEOUT_MS);

  try {
    const endpoint = new URL(
      process.env.REVERSE_GEOCODE_ENDPOINT || DEFAULT_REVERSE_GEOCODE_ENDPOINT
    );
    endpoint.searchParams.set("format", "jsonv2");
    endpoint.searchParams.set("lat", normalizedLatitude.toString());
    endpoint.searchParams.set("lon", normalizedLongitude.toString());
    endpoint.searchParams.set("zoom", "16");
    endpoint.searchParams.set("addressdetails", "1");

    const response = await fetch(endpoint, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "User-Agent":
          process.env.REVERSE_GEOCODE_USER_AGENT ||
          "child-tracker-status-monitor/1.0",
      },
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`Reverse geocode failed with HTTP ${response.status}`);
    }

    const data = await response.json();
    const displayName = data?.display_name?.toString().trim() || "";
    if (displayName) {
      return displayName;
    }
  } catch (error) {
    console.warn("[reverse-geocode] fallback", {
      latitude: normalizedLatitude,
      longitude: normalizedLongitude,
      reason: error.message,
    });
  } finally {
    clearTimeout(timeoutHandle);
  }

  return buildFallbackPlaceName(normalizedLatitude, normalizedLongitude);
}

module.exports = {
  reverseGeocodeCoordinates,
  buildFallbackPlaceName,
};
