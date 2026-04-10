const { firestore } = require("../firebase");

exports.getSettings = async (req,res)=>{
  const snap=await firestore.collection("system_settings").get();
  const list={};
  snap.forEach(d=>list[d.data().key]=d.data().value);
  res.send(list);
};

exports.updateSettings = async (req,res)=>{
  const {key,value,admin_id}=req.body;

  await firestore.collection("system_settings").doc(key).set({
    key,value,
    updated_by:admin_id,
    updated_at:Date.now()
  });

  res.send("updated");
};
