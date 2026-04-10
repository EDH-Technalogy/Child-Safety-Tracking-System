function notFoundHandler(req, res, next) {
  res.status(404).json({
    error: `Route not found: ${req.method} ${req.originalUrl}`,
  });
}

function errorHandler(err, req, res, next) {
  if (res.headersSent) {
    return next(err);
  }

  const statusCode = err.status || err.statusCode || 500;
  const message = err.message || "Internal server error";

  console.error(
    `[ERROR] ${req.method} ${req.originalUrl} -> ${statusCode}: ${message}`
  );

  if (err.stack) {
    console.error(err.stack);
  }

  res.status(statusCode).json({
    error: message,
  });
}

module.exports = {
  notFoundHandler,
  errorHandler,
};
