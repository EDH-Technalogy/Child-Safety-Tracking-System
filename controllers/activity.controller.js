const { firestore } = require("../firebase");

exports.addLog = async (req,res)=>{
  await firestore.collection("activity_logs").add({
    child_id:req.body.child_id,
    event_type:req.body.event_type,
    description:req.body.description,
    created_at:Date.now()
  });

  res.send("log saved");
};

// Get activity logs for a child
exports.getLogs = async (req, res) => {
  try {
    const { child_id } = req.params;
    const snapshot = await firestore
      .collection("activity_logs")
      .where("child_id", "==", child_id)
      .get();
    
    const logs = [];
    snapshot.forEach((doc) => {
      logs.push({
        id: doc.id,
        ...doc.data()
      });
    });

    logs.sort((a, b) => (b.created_at || 0) - (a.created_at || 0));
    
    res.json(logs);
  } catch (error) {
    res.status(500).send(error.message);
  }
};
