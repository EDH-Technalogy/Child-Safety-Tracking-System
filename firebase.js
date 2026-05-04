require("dotenv").config();
const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL:
      process.env.FIREBASE_DATABASE_URL ||
      "https://child-safety-tracking-default-rtdb.firebaseio.com",
  });
}

const realtimeDB = admin.database();
const db = admin.firestore();
const firestore = db;
const auth = admin.auth();

module.exports = { admin, auth, db, realtimeDB, firestore };



