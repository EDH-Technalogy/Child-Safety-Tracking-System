const { firestore } = require("../firebase");

function createHttpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

exports.getSettings = async (req, res, next) => {
  try {
    const snap = await firestore.collection("system_settings").get();
    const list = {};
    snap.forEach((doc) => {
      const data = doc.data() || {};
      if (data.key) {
        list[data.key] = data.value;
      }
    });

    res.json(list);
  } catch (error) {
    next(error);
  }
};

exports.updateSettings = async (req, res, next) => {
  try {
    const key = req.body.key?.toString().trim();
    if (!key) {
      throw createHttpError(400, "key is required");
    }

    const value = req.body.value;
    const updatedAt = Date.now();

    await firestore.collection("system_settings").doc(key).set({
      key,
      value,
      updated_by: req.auth?.id || null,
      updated_at: updatedAt,
    });

    res.json({
      key,
      value,
      updated_at: updatedAt,
      message: "Settings updated",
    });
  } catch (error) {
    next(error);
  }
};
