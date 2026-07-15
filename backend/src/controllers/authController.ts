import { Request, Response } from "express";
import bcrypt from "bcrypt";
import User, { type IUser } from "../models/User.js";
import type { HydratedDocument } from "mongoose";
import jwt from "jsonwebtoken";
import crypto from "crypto";
import Session from "../models/Session.js";
import { config } from "../config/index.js";
import { OAuth2Client } from "google-auth-library";

const ACCESS_TOKEN_TTL = "30m"; // thường là dưới 15m
const REFRESH_TOKEN_TTL = 14 * 24 * 60 * 60 * 1000; // 14 ngày
const googleClient = new OAuth2Client();

const createAuthenticatedSession = async (
  user: HydratedDocument<IUser>,
  res: Response
) => {
  const accessToken = jwt.sign(
    { userId: user._id },
    config.ACCESS_TOKEN_SECRET,
    { expiresIn: ACCESS_TOKEN_TTL }
  );

  const refreshToken = crypto.randomBytes(64).toString("hex");
  await Session.create({
    userId: user._id,
    refreshToken,
    expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL),
  });

  res.cookie("refreshToken", refreshToken, {
    httpOnly: true,
    secure: true,
    sameSite: "none",
    maxAge: REFRESH_TOKEN_TTL,
  });

  return accessToken;
};

const createAvailableUsername = async (email: string) => {
  const localPart = email.split("@")[0] || "flowchat";
  let base = localPart
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9._]/g, "")
    .replace(/^[._]+|[._]+$/g, "")
    .slice(0, 24);
  if (base.length < 3) base = `user${base}`;

  let candidate = base;
  let suffix = 0;
  while (await User.exists({ username: candidate })) {
    suffix += 1;
    candidate = `${base.slice(0, 24 - String(suffix).length)}${suffix}`;
  }
  return candidate;
};

export const signUp = async (req: Request, res: Response): Promise<any> => {
  try {
    const { username, password, email, firstName, lastName } = req.body;

    if (!username || !password || !email || !firstName || !lastName) {
      return res.status(400).json({
        message: "Không thể thiếu username, password, email, firstName, và lastName",
      });
    }

    // kiểm tra username tồn tại chưa
    const normalizedUsername = String(username).trim().toLowerCase();
    const normalizedEmail = String(email).trim().toLowerCase();
    const duplicate = await User.findOne({
      $or: [{ username: normalizedUsername }, { email: normalizedEmail }],
    });

    if (duplicate) {
      return res.status(409).json({
        message:
          duplicate.username === normalizedUsername
            ? "Tên đăng nhập đã tồn tại"
            : "Email đã được sử dụng",
      });
    }

    // mã hoá password
    const hashedPassword = await bcrypt.hash(password, 10); // salt = 10

    // tạo user mới
    await User.create({
      username: normalizedUsername,
      hashedPassword,
      email: normalizedEmail,
      displayName: `${lastName} ${firstName}`,
    });

    // return
    return res.sendStatus(204);
  } catch (error) {
    console.error("Lỗi khi gọi signUp", error);
    return res.status(500).json({ message: "Lỗi hệ thống" });
  }
};

export const signIn = async (req: Request, res: Response): Promise<any> => {
  try {
    // lấy inputs
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ message: "Thiếu username hoặc password." });
    }

    // lấy hashedPassword trong db để so với password input
    const user = await User.findOne({ username });

    if (!user) {
      return res
        .status(401)
        .json({ message: "username hoặc password không chính xác" });
    }

    // kiểm tra password
    const passwordCorrect = user.hashedPassword
      ? await bcrypt.compare(password, user.hashedPassword)
      : false;

    if (!passwordCorrect) {
      return res
        .status(401)
        .json({ message: "username hoặc password không chính xác" });
    }

    const accessToken = await createAuthenticatedSession(user, res);

    // trả access token về trong res
    return res
      .status(200)
      .json({ message: `User ${user.displayName} đã logged in!`, accessToken });
  } catch (error) {
    console.error("Lỗi khi gọi signIn", error);
    return res.status(500).json({ message: "Lỗi hệ thống" });
  }
};

export const signInWithGoogle = async (
  req: Request,
  res: Response
): Promise<any> => {
  try {
    const idToken = String(req.body?.idToken || "").trim();
    if (!idToken) {
      return res.status(400).json({ message: "Thiếu Google ID token." });
    }
    if (config.GOOGLE_CLIENT_IDS.length === 0) {
      console.error("GOOGLE_CLIENT_IDS chưa được cấu hình.");
      return res.status(503).json({
        message: "Đăng nhập Google chưa được cấu hình trên máy chủ.",
      });
    }

    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: config.GOOGLE_CLIENT_IDS,
    });
    const payload = ticket.getPayload();
    const googleId = payload?.sub;
    const email = payload?.email?.trim().toLowerCase();

    if (!payload || !googleId || !email || payload.email_verified !== true) {
      return res.status(401).json({
        message: "Tài khoản Google chưa có email được xác minh.",
      });
    }

    let user = await User.findOne({ googleId });
    if (!user) {
      user = await User.findOne({ email });
      if (user) {
        if (user.googleId && user.googleId !== googleId) {
          return res.status(409).json({
            message: "Email này đã liên kết với một tài khoản Google khác.",
          });
        }
        user.googleId = googleId;
        if (!user.avatarUrl && payload.picture) user.avatarUrl = payload.picture;
        await user.save();
      } else {
        user = await User.create({
          username: await createAvailableUsername(email),
          googleId,
          email,
          displayName: payload.name?.trim() || email.split("@")[0],
          avatarUrl: payload.picture,
        });
      }
    }

    const accessToken = await createAuthenticatedSession(user, res);
    return res.status(200).json({
      message: `User ${user.displayName} đã đăng nhập bằng Google!`,
      accessToken,
    });
  } catch (error) {
    console.error("Lỗi khi đăng nhập Google", error);
    return res.status(401).json({ message: "Google ID token không hợp lệ." });
  }
};

export const signOut = async (req: Request, res: Response): Promise<any> => {
  try {
    // lấy refresh token từ cookie
    const token = req.cookies?.refreshToken;

    if (token) {
      // xoá refresh token trong Session
      await Session.deleteOne({ refreshToken: token });

      // xoá cookie
      res.clearCookie("refreshToken");
    }

    return res.sendStatus(204);
  } catch (error) {
    console.error("Lỗi khi gọi signOut", error);
    return res.status(500).json({ message: "Lỗi hệ thống" });
  }
};

// tạo access token mới từ refresh token
export const refreshToken = async (req: Request, res: Response): Promise<any> => {
  try {
    // lấy refresh token từ cookie
    const token = req.cookies?.refreshToken;
    if (!token) {
      return res.status(401).json({ message: "Token không tồn tại." });
    }

    // so với refresh token trong db
    const session = await Session.findOne({ refreshToken: token });

    if (!session) {
      return res.status(403).json({ message: "Token không hợp lệ hoặc đã hết hạn" });
    }

    // kiểm tra hết hạn chưa
    if (session.expiresAt < new Date()) {
      return res.status(403).json({ message: "Token đã hết hạn." });
    }

    // tạo access token mới
    const accessToken = jwt.sign(
      {
        userId: session.userId,
      },
      config.ACCESS_TOKEN_SECRET,
      { expiresIn: ACCESS_TOKEN_TTL }
    );

    // return
    return res.status(200).json({ accessToken });
  } catch (error) {
    console.error("Lỗi khi gọi refreshToken", error);
    return res.status(500).json({ message: "Lỗi hệ thống" });
  }
};
