import dotenv from "dotenv";
dotenv.config();

function getEnv(key: string, required = true): string {
  const val = process.env[key];
  if (!val && required) {
    throw new Error(`Environment variable ${key} is missing from env configuration`);
  }
  return val || "";
}

export const config = {
  PORT: process.env.PORT ? parseInt(process.env.PORT, 10) : 5001,
  MONGODB_CONNECTIONSTRING: getEnv("MONGODB_CONNECTIONSTRING"),
  CLIENT_URL: getEnv("CLIENT_URL"),
  ACCESS_TOKEN_SECRET: getEnv("ACCESS_TOKEN_SECRET"),
  GOOGLE_CLIENT_IDS: getEnv("GOOGLE_CLIENT_IDS", false)
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
  CLOUDINARY_CLOUD_NAME: getEnv("CLOUDINARY_CLOUD_NAME"),
  CLOUDINARY_API_KEY: getEnv("CLOUDINARY_API_KEY"),
  CLOUDINARY_API_SECRET: getEnv("CLOUDINARY_API_SECRET"),
};
