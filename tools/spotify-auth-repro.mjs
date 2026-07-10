#!/usr/bin/env node
// Local reproduction of the sp_dc -> TOTP -> access token -> currently-playing
// flow implemented in the Swift app (see ../LyricsPiP/Services/SpotifyTOTP.swift
// and ../LyricsPiP/Services/SpotifyWebSessionClient.swift). Lets you iterate on
// the exact request shape in seconds instead of the full
// push -> CI -> download -> sideload -> device loop.
//
// Usage:
//   node tools/spotify-auth-repro.mjs <sp_dc value>
//   SPOTIFY_SP_DC=... node tools/spotify-auth-repro.mjs
//
// Requires Node 18+ (global fetch). Run with `node`, no npm install needed.

import crypto from "node:crypto";

const SECRETS_URL =
  "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true";
const USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

const spDc = process.argv[2] || process.env.SPOTIFY_SP_DC;
if (!spDc) {
  console.error("Usage: node tools/spotify-auth-repro.mjs <sp_dc value>");
  console.error("   or: SPOTIFY_SP_DC=... node tools/spotify-auth-repro.mjs");
  process.exit(1);
}

async function fetchLatestSecret() {
  const res = await fetch(SECRETS_URL);
  if (!res.ok) throw new Error(`secrets fetch failed: HTTP ${res.status}`);
  const dict = await res.json();
  const version = Math.max(...Object.keys(dict).map(Number));
  return { version, cipherBytes: dict[String(version)] };
}

// Mirrors SpotifyTOTP.secretKeyData(fromCipherBytes:) in the Swift app.
function secretKeyBytes(cipherBytes) {
  const transformed = cipherBytes.map((value, index) => value ^ ((index % 33) + 9));
  const joined = transformed.map(String).join("");
  return Buffer.from(joined, "utf8");
}

// Standard RFC 6238 TOTP (HMAC-SHA1, 6 digits, 30s period).
function totp(keyBytes, unixTime, digits = 6, period = 30) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(unixTime / period)));
  const hmac = crypto.createHmac("sha1", keyBytes).update(counter).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const truncated =
    ((hmac[offset] & 0x7f) << 24) |
    (hmac[offset + 1] << 16) |
    (hmac[offset + 2] << 8) |
    hmac[offset + 3];
  const code = truncated % 10 ** digits;
  return String(code).padStart(digits, "0");
}

async function fetchServerTime() {
  const res = await fetch("https://open.spotify.com/", {
    method: "HEAD",
    headers: { "User-Agent": USER_AGENT },
  });
  const dateHeader = res.headers.get("date");
  if (!dateHeader) return Math.floor(Date.now() / 1000);
  return Math.floor(new Date(dateHeader).getTime() / 1000);
}

async function requestAccessToken(reason) {
  const serverTime = await fetchServerTime();
  console.log(`[time] server time: ${serverTime}`);

  const { version, cipherBytes } = await fetchLatestSecret();
  console.log(`[totp] using secret version ${version}`);

  const keyBytes = secretKeyBytes(cipherBytes);
  const code = totp(keyBytes, serverTime);
  console.log(`[totp] code: ${code}`);

  const url = new URL("https://open.spotify.com/api/token");
  url.searchParams.set("reason", reason);
  url.searchParams.set("productType", "web-player");
  url.searchParams.set("totp", code);
  url.searchParams.set("totpServer", code);
  url.searchParams.set("totpVer", String(version));

  const res = await fetch(url, {
    headers: {
      Cookie: `sp_dc=${spDc}`,
      "User-Agent": USER_AGENT,
      Accept: "application/json",
      Referer: "https://open.spotify.com/",
      "App-Platform": "WebPlayer",
    },
  });

  const bodyText = await res.text();
  console.log(`[token:${reason}] HTTP ${res.status}`);
  if (!res.ok) {
    console.log(`[token:${reason}] body: ${bodyText}`);
    throw new Error(`token request failed: HTTP ${res.status}`);
  }

  const data = JSON.parse(bodyText);
  if (data.isAnonymous) {
    throw new Error("isAnonymous=true -> sp_dc cookie is invalid/expired");
  }
  console.log(
    `[token:${reason}] success, expires ${new Date(data.accessTokenExpirationTimestampMs).toISOString()}`
  );
  return data.accessToken;
}

async function fetchCurrentlyPlaying(accessToken) {
  const res = await fetch("https://api.spotify.com/v1/me/player/currently-playing", {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "User-Agent": USER_AGENT,
    },
  });
  console.log(`[currently-playing] HTTP ${res.status}`);
  if (res.status === 429) {
    console.log(`[currently-playing] Retry-After: ${res.headers.get("retry-after")}`);
    return;
  }
  if (res.status === 204) {
    console.log("[currently-playing] no track playing");
    return;
  }
  const body = await res.text();
  console.log(`[currently-playing] body: ${body}`);
}

async function main() {
  let token;
  try {
    token = await requestAccessToken("transport");
  } catch (err) {
    console.log(`[token] transport failed: ${err.message}, retrying with reason=init`);
    token = await requestAccessToken("init");
  }
  await fetchCurrentlyPlaying(token);
}

main().catch((err) => {
  console.error("FAILED:", err.message);
  process.exit(1);
});
