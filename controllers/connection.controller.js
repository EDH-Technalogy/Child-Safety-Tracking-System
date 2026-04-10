const { realtimeDB, firestore } = require("../firebase");

exports.updateConnection = async (req,res)=>{
  const {child_id,status,lat,lng}=req.body;
  const time=Date.now();

  await realtimeDB.ref(`live_tracking/${child_id}/connection`).set({
    status,time
  });

  await firestore.collection("connection_logs").add({
    child_id,status,
    latitude:lat,longitude:lng,
    event_time:time
  });

  res.send("connection saved");
};
