require("dotenv").config();
const nodemailer = require("nodemailer");

let transporter;

function getTransporter() {
  if (transporter) {
    return transporter;
  }

  const user = process.env.EMAIL_USER || process.env.SMTP_USER;
  const pass = process.env.EMAIL_PASS || process.env.SMTP_PASS;

  if (!user || !pass) {
    throw new Error("EMAIL_USER and EMAIL_PASS are required");
  }

  transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
      user,
      pass,
    },
  });

  console.log("[email.service] Gmail transporter configured", { user });
  return transporter;
}

async function sendMail({ to, subject, text }) {
  const mailer = getTransporter();

  console.log("[email.service] Sending email", { to, subject });

  await mailer.sendMail({
    from: process.env.EMAIL_FROM || `"Child Tracker" <${process.env.EMAIL_USER}>`,
    to,
    subject,
    text,
  });

  console.log("[email.service] Email sent successfully", { to });
  return { skipped: false };
}

async function sendOtpEmail(email, otp, type) {
  const action = type === "forgot" ? "reset your password" : "verify your account";

  return sendMail({
    to: email,
    subject: "Your OTP Code",
    text: `Your OTP is: ${otp}. It expires in 5 minutes.\n\nUse this code to ${action}.`,
  });
}

async function sendPasswordResetLink(email, link) {
  return sendMail({
    to: email,
    subject: "Reset your Child Tracker password",
    text: `Use this secure link to reset your password:\n\n${link}`,
  });
}

module.exports = {
  sendOtpEmail,
  sendPasswordResetLink,
};
