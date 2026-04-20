const express = require("express");
const cors = require("cors");
const { realtimeDB } = require("./firebase");
const requestLogger = require("./middleware/requestLogger");
const { notFoundHandler, errorHandler } = require("./middleware/errorHandler");
const { initLiveGeofenceMonitor } = require("./utils/live-geofence-monitor");

const app = express();

const corsOptions = {
  origin(origin, callback) {
    callback(null, origin || true);
  },
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
  credentials: false,
  optionsSuccessStatus: 204,
};

// Enable CORS properly for Flutter Web and API clients
app.use(cors(corsOptions));
app.use(express.json());
app.use(requestLogger);

// Import all routes
const userRoutes = require("./routes/user.routes");
const childRoutes = require("./routes/child.routes");
const deviceRoutes = require("./routes/device.routes");
const locationRoutes = require("./routes/location.routes");
const alertRoutes = require("./routes/alert.routes");
const connectionRoutes = require("./routes/connection.routes");
const activityRoutes = require("./routes/activity.routes");
const summaryRoutes = require("./routes/summary.routes");
const adminRoutes = require("./routes/admin.routes");
const settingsRoutes = require("./routes/settings.routes");
const geofenceRoutes = require("./routes/geofence.routes");

// Mount all routes
app.use("/api/users", userRoutes);
app.use("/api/children", childRoutes);
app.use("/api/devices", deviceRoutes);
app.use("/api/locations", locationRoutes);
app.use("/api/alerts", alertRoutes);
app.use("/api/connections", connectionRoutes);
app.use("/api/activity", activityRoutes);
app.use("/api/summary", summaryRoutes);
app.use("/api/admin", adminRoutes);
app.use("/api/settings", settingsRoutes);
app.use("/api/geofence", geofenceRoutes);

// Root endpoint
app.get("/", (req, res) => {
    res.send("Child Safety GPS Tracking System Backend is Running!");
});

// Test endpoint for database connection
app.get("/test", async (req, res) => {
    await realtimeDB.ref("test").set({
        name: "ahmad",
        age: 20,
        timestamp: Date.now()
    });
    res.send("Database connection successful!");
});

app.use(notFoundHandler);
app.use(errorHandler);

const PORT = process.env.PORT || 3000;
initLiveGeofenceMonitor();
app.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
    console.log("API Endpoints:");
    console.log("- POST   /api/users/register");
    console.log("- POST   /api/users/login");
    console.log("- GET    /api/users/:id");
    console.log("- PUT    /api/users/:id");
    console.log("- POST   /api/children/add");
    console.log("- GET    /api/children/:user_id");
    console.log("- GET    /api/children/child/:child_id");
    console.log("- PUT    /api/children/:child_id");
    console.log("- DELETE /api/children/:child_id");
    console.log("- POST   /api/devices/register");
    console.log("- POST   /api/locations/update");
    console.log("- GET    /api/locations/live/:child_id");
    console.log("- GET    /api/locations/history/:child_id");
    console.log("- GET    /api/locations/route/:child_id/:date");
    console.log("- POST   /api/alerts/send");
    console.log("- GET    /api/alerts/:child_id");
    console.log("- POST   /api/geofence/safe-zone");
    console.log("- GET    /api/geofence/safe-zones/:child_id");
    console.log("- POST   /api/geofence/check-location");
    console.log("- POST   /api/admin/login");
    console.log("- GET    /api/admin/stats/system");
});
