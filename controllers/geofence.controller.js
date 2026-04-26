const { firestore } = require("../firebase");
const {
  createHttpError,
  getChildWithAccessOrThrow,
  getChildOrThrow,
  isAdminRequest,
} = require("../utils/child-access");
const {
  removeSafeZoneMirror,
  upsertSafeZoneMirror,
} = require("../utils/safe-zone-sync");
const { appendChildLog } = require("../utils/child-logs");

const MIN_RADIUS_METERS = 50;
const MAX_RADIUS_METERS = 50000;

function calculateDistance(lat1, lon1, lat2, lon2) {
  const earthRadiusMeters = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

function parseCoordinate(value, fieldName) {
  const numericValue = Number(value);

  if (!Number.isFinite(numericValue)) {
    throw createHttpError(400, `${fieldName} must be a valid number`);
  }

  return numericValue;
}

function validateCoordinates(latitude, longitude) {
  if (latitude < -90 || latitude > 90) {
    throw createHttpError(400, "latitude must be between -90 and 90");
  }

  if (longitude < -180 || longitude > 180) {
    throw createHttpError(400, "longitude must be between -180 and 180");
  }
}

function parseRadius(value) {
  const numericRadius = Number(value);

  if (!Number.isFinite(numericRadius)) {
    throw createHttpError(400, "radius must be a valid number");
  }

  const roundedRadius = Math.round(numericRadius);

  if (
    roundedRadius < MIN_RADIUS_METERS ||
    roundedRadius > MAX_RADIUS_METERS
  ) {
    throw createHttpError(
      400,
      `radius must be between ${MIN_RADIUS_METERS} and ${MAX_RADIUS_METERS} meters`
    );
  }

  return roundedRadius;
}

function normalizeZoneStatus(status) {
  if (status === undefined) {
    return undefined;
  }

  const normalizedStatus = status.toString().trim().toLowerCase();
  if (!["active", "inactive"].includes(normalizedStatus)) {
    throw createHttpError(400, "status must be active or inactive");
  }

  return normalizedStatus;
}

function normalizeSearchTerm(value) {
  return value?.toString().trim().toLowerCase() || "";
}

function zoneMatchesSearch(zone, searchTerm) {
  if (!searchTerm) {
    return true;
  }

  return [
    zone.name,
    zone.child_name,
    zone.child_id,
  ].some((value) => value?.toString().toLowerCase().includes(searchTerm));
}

async function resolveChildMetadata({
  childId,
  fallbackChildData = null,
  childCache = null,
}) {
  if (!childId) {
    return {};
  }

  if (fallbackChildData) {
    return fallbackChildData;
  }

  if (childCache?.has(childId)) {
    return childCache.get(childId);
  }

  let childData = {};
  try {
    const { childDoc } = await getChildOrThrow(childId);
    childData = childDoc.data() || {};
  } catch (error) {
    childData = {};
  }

  if (childCache) {
    childCache.set(childId, childData);
  }
  return childData;
}

async function hydrateSafeZoneRecord(doc, options = {}) {
  const data = doc.data() || {};
  const childId = data.child_id?.toString().trim() || "";
  const childData = await resolveChildMetadata({
    childId,
    fallbackChildData: options.fallbackChildData,
    childCache: options.childCache,
  });

  return {
    id: doc.id,
    ...data,
    child_id: childId,
    user_id:
      data.user_id?.toString().trim() ||
      childData.user_id?.toString().trim() ||
      "",
    child_name:
      data.child_name?.toString().trim() ||
      childData.name?.toString().trim() ||
      "",
  };
}

async function listAuthorizedSafeZones(req, searchTerm = "") {
  const normalizedSearch = normalizeSearchTerm(searchTerm);
  const zoneSnap = await firestore.collection("safe_zones").get();
  const childCache = new Map();
  let ownedChildrenById = null;

  if (!isAdminRequest(req)) {
    const ownedChildrenSnap = await firestore
      .collection("children")
      .where("user_id", "==", req.auth?.id || "")
      .get();

    ownedChildrenById = new Map(
      ownedChildrenSnap.docs.map((doc) => [doc.id, doc.data() || {}])
    );
  }

  const safeZones = [];
  for (const doc of zoneSnap.docs) {
    const data = doc.data() || {};
    const childId = data.child_id?.toString().trim() || "";
    if (!childId) {
      continue;
    }

    if (!isAdminRequest(req)) {
      if (!ownedChildrenById?.has(childId)) {
        continue;
      }
    }

    const zone = await hydrateSafeZoneRecord(doc, {
      fallbackChildData: ownedChildrenById?.get(childId),
      childCache,
    });

    if (!zoneMatchesSearch(zone, normalizedSearch)) {
      continue;
    }

    safeZones.push(zone);
  }

  safeZones.sort(
    (a, b) =>
      (b.updated_at || b.created_at || 0) - (a.updated_at || a.created_at || 0)
  );

  return safeZones;
}

async function getZoneOrThrow(zoneId) {
  const zoneRef = firestore.collection("safe_zones").doc(zoneId);
  const zoneDoc = await zoneRef.get();

  if (!zoneDoc.exists) {
    throw createHttpError(404, "Safe zone not found");
  }

  return { zoneRef, zoneDoc };
}

function buildZoneCheckResponse(zones, latitude, longitude) {
  let inAnyZone = false;
  let currentZone = null;

  const zoneDistances = zones.map((zone) => {
    const distance = calculateDistance(
      latitude,
      longitude,
      zone.latitude,
      zone.longitude
    );
    const isInZone = distance <= zone.radius;

    if (isInZone && !inAnyZone) {
      inAnyZone = true;
      currentZone = {
        id: zone.id,
        name: zone.name,
      };
    }

    return {
      id: zone.id,
      name: zone.name,
      distance: Math.round(distance),
      in_zone: isInZone,
    };
  });

  return {
    in_zone: inAnyZone,
    current_zone: currentZone,
    zones: zoneDistances,
  };
}

exports.createSafeZone = async (req, res, next) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    const name = req.body.name?.toString().trim();

    if (!childId || !name) {
      throw createHttpError(400, "child_id and name are required");
    }

    const latitude = parseCoordinate(req.body.latitude, "latitude");
    const longitude = parseCoordinate(req.body.longitude, "longitude");
    const radius =
      req.body.radius !== undefined
        ? parseRadius(req.body.radius)
        : 100;
    validateCoordinates(latitude, longitude);

    const { childDoc } = await getChildWithAccessOrThrow(req, childId);
    const childData = childDoc.data() || {};
    const childName = childData.name?.toString().trim() || "";

    const createdAt = Date.now();
    const zonePayload = {
      child_id: childId,
      child_name: childName,
      user_id: childData.user_id || "",
      name,
      latitude,
      longitude,
      radius,
      created_at: createdAt,
      updated_at: createdAt,
      status: "active",
      created_by: req.auth?.id || "",
      created_by_role: req.auth?.role || "",
    };
    const zone = await firestore.collection("safe_zones").add(zonePayload);
    await upsertSafeZoneMirror(zone.id, zonePayload);
    await appendChildLog({
      childId,
      trackingKey: "",
      parentUserId: childData.user_id || "",
      type: "SAFE_ZONE_CREATED",
      message: `Safe zone "${name}" created.`,
      timestamp: createdAt,
      metadata: {
        zoneId: zone.id,
        zoneName: name,
        radius,
        latitude,
        longitude,
        actorId: req.auth?.id || "",
        actorRole: req.auth?.role || "",
      },
    });

    console.info("[geofence.createSafeZone]", {
      requestedChildId: req.body.child_id?.toString().trim() || "",
      requestedChildName: req.body.child_name?.toString().trim() || "",
      centerSource: req.body.center_source?.toString().trim() || "",
      childId,
      childName,
      actorId: req.auth?.id,
      actorRole: req.auth?.role,
      latitude,
      longitude,
      radius,
    });

    res.status(201).json({
      zone_id: zone.id,
      message: "Safe zone created successfully",
    });
  } catch (error) {
    next(error);
  }
};

exports.searchSafeZones = async (req, res, next) => {
  try {
    const searchTerm = req.query.search?.toString().trim() || "";
    const safeZones = await listAuthorizedSafeZones(req, searchTerm);

    console.info("[geofence.searchSafeZones]", {
      actorId: req.auth?.id,
      actorRole: req.auth?.role,
      searchTerm,
      results: safeZones.length,
    });

    res.json(safeZones);
  } catch (error) {
    next(error);
  }
};

exports.getSafeZones = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    const { childDoc } = await getChildWithAccessOrThrow(req, childId);
    const childData = childDoc.data() || {};

    const snap = await firestore
      .collection("safe_zones")
      .where("child_id", "==", childId)
      .get();

    const safeZones = await Promise.all(
      snap.docs.map((doc) =>
        hydrateSafeZoneRecord(doc, {
          fallbackChildData: childData,
        })
      )
    );

    res.json(safeZones);
  } catch (error) {
    next(error);
  }
};

exports.updateSafeZone = async (req, res, next) => {
  try {
    const { zoneRef, zoneDoc } = await getZoneOrThrow(req.params.zone_id);
    const zoneData = zoneDoc.data() || {};

    const { childDoc } = await getChildWithAccessOrThrow(req, zoneData.child_id);
    const childData = childDoc.data() || {};

    const updates = {};

    if (req.body.name !== undefined) {
      const name = req.body.name?.toString().trim();
      if (!name) {
        throw createHttpError(400, "name cannot be empty");
      }
      updates.name = name;
    }

    if (req.body.latitude !== undefined) {
      updates.latitude = parseCoordinate(req.body.latitude, "latitude");
    }

    if (req.body.longitude !== undefined) {
      updates.longitude = parseCoordinate(req.body.longitude, "longitude");
    }

    if (
      updates.latitude !== undefined ||
      updates.longitude !== undefined
    ) {
      validateCoordinates(
        updates.latitude ?? zoneData.latitude,
        updates.longitude ?? zoneData.longitude
      );
    }

    if (req.body.radius !== undefined) {
      updates.radius = parseRadius(req.body.radius);
    }

    if (req.body.status !== undefined) {
      updates.status = normalizeZoneStatus(req.body.status);
    }

    const resolvedChildName =
      childData.name?.toString().trim() ||
      zoneData.child_name?.toString().trim() ||
      "";
    const resolvedUserId =
      zoneData.user_id?.toString().trim() ||
      childData.user_id?.toString().trim() ||
      "";

    if (resolvedChildName && resolvedChildName !== zoneData.child_name) {
      updates.child_name = resolvedChildName;
    }

    if (resolvedUserId && resolvedUserId !== zoneData.user_id) {
      updates.user_id = resolvedUserId;
    }

    if (Object.keys(updates).length === 0) {
      throw createHttpError(400, "No safe zone fields provided to update");
    }

    updates.updated_at = Date.now();
    updates.updated_by = req.auth?.id || "";
    updates.updated_by_role = req.auth?.role || "";

    await zoneRef.update(updates);
    await upsertSafeZoneMirror(req.params.zone_id, {
      ...zoneData,
      ...updates,
      child_id: zoneData.child_id,
      child_name: resolvedChildName,
      user_id: resolvedUserId,
    });
    await appendChildLog({
      childId: zoneData.child_id,
      trackingKey: "",
      parentUserId: resolvedUserId,
      type: "SAFE_ZONE_UPDATED",
      message: `Safe zone "${updates.name || zoneData.name || "Safe Zone"}" updated.`,
      timestamp: updates.updated_at,
      metadata: {
        zoneId: req.params.zone_id,
        updatedFields: Object.keys(updates),
        radius: updates.radius ?? zoneData.radius ?? null,
        latitude: updates.latitude ?? zoneData.latitude ?? null,
        longitude: updates.longitude ?? zoneData.longitude ?? null,
        actorId: req.auth?.id || "",
        actorRole: req.auth?.role || "",
      },
    });

    console.info("[geofence.updateSafeZone]", {
      zoneId: req.params.zone_id,
      requestedChildId: req.body.child_id?.toString().trim() || "",
      requestedChildName: req.body.child_name?.toString().trim() || "",
      centerSource: req.body.center_source?.toString().trim() || "",
      childId: zoneData.child_id,
      childName: resolvedChildName,
      actorId: req.auth?.id,
      actorRole: req.auth?.role,
      updatedFields: Object.keys(updates),
    });

    res.json({ message: "Safe zone updated successfully" });
  } catch (error) {
    next(error);
  }
};

exports.deleteSafeZone = async (req, res, next) => {
  try {
    const { zoneRef, zoneDoc } = await getZoneOrThrow(req.params.zone_id);
    const zoneData = zoneDoc.data() || {};

    await getChildWithAccessOrThrow(req, zoneData.child_id);
    await zoneRef.delete();
    await removeSafeZoneMirror(req.params.zone_id, {
      childId: zoneData.child_id,
    });

    console.info("[geofence.deleteSafeZone]", {
      zoneId: req.params.zone_id,
      childId: zoneData.child_id,
      actorId: req.auth?.id,
      actorRole: req.auth?.role,
    });

    res.json({ message: "Safe zone deleted successfully" });
  } catch (error) {
    next(error);
  }
};

exports.checkLocation = async (req, res, next) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    const latitude = parseCoordinate(req.body.latitude, "latitude");
    const longitude = parseCoordinate(req.body.longitude, "longitude");
    validateCoordinates(latitude, longitude);

    await getChildWithAccessOrThrow(req, childId);

    const snap = await firestore
      .collection("safe_zones")
      .where("child_id", "==", childId)
      .where("status", "==", "active")
      .get();

    if (snap.empty) {
      return res.json({
        in_zone: false,
        current_zone: null,
        zones: [],
        message: "No safe zones defined",
      });
    }

    const zones = snap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    console.info("[geofence.checkLocation]", {
      childId,
      actorId: req.auth?.id,
      actorRole: req.auth?.role,
      latitude,
      longitude,
      zoneCount: zones.length,
    });

    res.json(buildZoneCheckResponse(zones, latitude, longitude));
  } catch (error) {
    next(error);
  }
};

exports.getDefaultSettings = async (req, res, next) => {
  try {
    const snap = await firestore.collection("system_settings").get();
    const settings = {};

    snap.forEach((doc) => {
      settings[doc.data().key] = doc.data().value;
    });

    settings.default_safe_zone_radius =
      settings.default_safe_zone_radius || "100";
    settings.sos_hold_seconds = settings.sos_hold_seconds || "5";
    settings.location_update_interval =
      settings.location_update_interval || "30";
    settings.battery_alert_level = settings.battery_alert_level || "20";

    res.json(settings);
  } catch (error) {
    next(error);
  }
};

exports.updateDefaultSettings = async (req, res, next) => {
  try {
    const key = req.body.key?.toString().trim();
    const value = req.body.value;

    if (!key) {
      throw createHttpError(400, "key is required");
    }

    await firestore.collection("system_settings").doc(key).set({
      key,
      value,
      updated_by: req.auth?.id || "",
      updated_at: Date.now(),
    });

    res.json({ message: "Settings updated successfully" });
  } catch (error) {
    next(error);
  }
};
