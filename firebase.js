
const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://child-safety-tracking-default-rtdb.firebaseio.com"
});

const realtimeDB = admin.database();
const firestore = admin.firestore();

module.exports = { admin, realtimeDB, firestore };



