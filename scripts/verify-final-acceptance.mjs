#!/usr/bin/env node
import fs from "node:fs";
import crypto from "node:crypto";
import os from "node:os";
import pathModule from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

const requiredCases = [
  "ios-to-android-note",
  "android-to-ios-note",
  "ios-archive-before-ack",
  "android-archive-before-ack",
  "dropped-response-exact-retry",
  "multi-team-account-global-deletion",
  "locked-reboot-deletion-recovery",
  "universal-link-cold-launch",
  "provider-reauthentication",
  "android-ios-backup-roundtrip",
];
const fail = (message) => { console.error(`FAIL: ${message}`); process.exitCode = 1; };
const hash = (path) => crypto.createHash("sha256").update(fs.readFileSync(path))
  .digest("hex");
const command = (file, args, options = {}) => execFileSync(file, args, {
  encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...options,
}).trim();
const combinedCommand = (file, args) => {
  const result = spawnSync(file, args, { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`${file} exited ${result.status}`);
  return `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
};
const androidBuildTool = (name) => {
  const roots = [process.env.ANDROID_SDK_ROOT, process.env.ANDROID_HOME,
    pathModule.join(os.homedir(), "Library", "Android", "sdk")].filter(Boolean);
  for (const root of roots) {
    const directory = pathModule.join(root, "build-tools");
    if (!fs.existsSync(directory)) continue;
    const versions = fs.readdirSync(directory).sort((a, b) =>
      b.localeCompare(a, undefined, { numeric: true }));
    for (const version of versions) {
      const candidate = pathModule.join(directory, version, name);
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  throw new Error(`Android SDK build tool ${name} was not found`);
};
const path = process.argv[2];
if (!path) {
  fail("usage: node scripts/verify-final-acceptance.mjs <receipt.json>");
} else {
  let receipt;
  try { receipt = JSON.parse(fs.readFileSync(path, "utf8")); }
  catch { fail("receipt must be readable strict JSON"); }
  if (receipt) {
    if (receipt.schema !== "pinbook-final-acceptance-v1") fail("unexpected schema");
    if (receipt.status !== "PASS") {
      fail("receipt status is not PASS");
      process.exit();
    }
    const hex40 = /^[0-9a-f]{40}$/;
    const hex64 = /^[0-9a-f]{64}$/;
    for (const [platform, buildKey] of [["ios", "build"], ["android", "versionCode"]]) {
      const value = receipt[platform] ?? {};
      if (!hex40.test(value.sourceCommit ?? "")) fail(`${platform}.sourceCommit is invalid`);
      if (!hex64.test(value.artifactSHA256 ?? value.ipaSHA256 ?? "")) {
        fail(`${platform} artifact hash is invalid`);
      }
      if (!hex64.test(value.signingCertificateSHA256 ?? "")) {
        fail(`${platform} signing identity is invalid`);
      }
      if (!Number.isInteger(value[buildKey]) || value[buildKey] < 1) {
        fail(`${platform}.${buildKey} is invalid`);
      }
      if (!(value.sourcePath ?? "").startsWith("/")) fail(`${platform}.sourcePath must be absolute`);
    }
    if (!receipt.ios?.archivePath?.startsWith("/")) fail("ios.archivePath must be absolute");
    if (!receipt.ios?.ipaPath?.startsWith("/")) fail("ios.ipaPath must be absolute");
    if (!hex64.test(receipt.ios?.appBinarySHA256 ?? "")) {
      fail("ios.appBinarySHA256 is invalid");
    }
    if (!receipt.android?.artifactPath?.startsWith("/")) fail("android.artifactPath must be absolute");
    if (receipt.android?.artifactType !== "APK") fail("android.artifactType must be APK");
    if (!/^https:\/\//.test(receipt.staging?.origin ?? "")) fail("staging.origin must be HTTPS");
    if (!/^https:\/\//.test(receipt.staging?.aasaURL ?? "")) fail("staging.aasaURL must be HTTPS");
    if ((receipt.staging?.serverContractMigration ?? 0) < 28) fail("server migration 028+ is required");
    if (!(receipt.staging?.evidence ?? "").trim()) fail("staging evidence is required");
    for (const field of ["iphoneModel", "iphoneOS", "androidModel", "androidOS"]) {
      if (!(receipt.devices?.[field] ?? "").trim()) fail(`devices.${field} is required`);
    }
    const cases = new Map((receipt.matrix ?? []).map((item) => [item.id, item]));
    for (const id of requiredCases) {
      const item = cases.get(id);
      if (!item || item.status !== "PASS" || !(item.evidence ?? "").trim()) {
        fail(`matrix ${id} lacks real PASS evidence`);
      }
    }
    try {
      const ios = receipt.ios;
      if (command("git", ["-C", ios.sourcePath, "rev-parse", "HEAD"]) !== ios.sourceCommit) {
        fail("iOS source checkout does not match sourceCommit");
      }
      const appsRoot = pathModule.join(ios.archivePath, "Products", "Applications");
      const apps = fs.readdirSync(appsRoot).filter((name) => name.endsWith(".app"));
      if (apps.length !== 1) throw new Error("archive must contain exactly one top-level app");
      const appPath = pathModule.join(appsRoot, apps[0]);
      const info = JSON.parse(command("plutil", ["-convert", "json", "-o", "-",
        pathModule.join(appPath, "Info.plist")]));
      if (info.CFBundleIdentifier !== ios.appBundleID
          || info.CFBundleShortVersionString !== ios.version
          || Number(info.CFBundleVersion) !== ios.build) {
        fail("archive Info.plist does not match iOS identity/version/build");
      }
      const binaryPath = pathModule.join(appPath, info.CFBundleExecutable);
      if (hash(binaryPath) !== ios.appBinarySHA256) fail("archive app-binary hash mismatch");
      if (hash(ios.ipaPath) !== ios.ipaSHA256) fail("exported IPA hash mismatch");
      const signature = combinedCommand("codesign", ["-d", "--verbose=4", appPath]);
      if (!signature.includes(`TeamIdentifier=${ios.signingTeamID}`)) {
        fail("archive signing team mismatch");
      }
      const temporary = fs.mkdtempSync(pathModule.join(os.tmpdir(), "pinbook-acceptance-"));
      try {
        const prefix = pathModule.join(temporary, "certificate");
        execFileSync("codesign", ["-d", "--extract-certificates", prefix, appPath],
          { stdio: "ignore" });
        if (hash(`${prefix}0`) !== ios.signingCertificateSHA256) {
          fail("archive signing certificate hash mismatch");
        }
      } finally { fs.rmSync(temporary, { recursive: true, force: true }); }
      const android = receipt.android;
      if (command("git", ["-C", android.sourcePath, "rev-parse", "HEAD"])
          !== android.sourceCommit) fail("Android source checkout does not match sourceCommit");
      if (hash(android.artifactPath) !== android.artifactSHA256) {
        fail("Android artifact hash mismatch");
      }
      const badging = command(androidBuildTool("aapt"), ["dump", "badging",
        android.artifactPath]);
      const packageLine = badging.split("\n").find((line) => line.startsWith("package: ")) ?? "";
      const packageID = packageLine.match(/ name='([^']+)'/)?.[1];
      const versionCode = Number(packageLine.match(/ versionCode='([^']+)'/)?.[1]);
      const versionName = packageLine.match(/ versionName='([^']+)'/)?.[1];
      if (packageID !== android.packageID || versionCode !== android.versionCode
          || versionName !== android.versionName) {
        fail("Android package/version identity mismatch");
      }
      const signer = command(androidBuildTool("apksigner"), ["verify", "--print-certs",
        android.artifactPath]);
      const signerHash = signer.match(/Signer #1 certificate SHA-256 digest:\s*([0-9a-f:]+)/i)?.[1]
        ?.replaceAll(":", "").toLowerCase();
      if (signerHash !== android.signingCertificateSHA256) {
        fail("Android signing certificate hash mismatch");
      }
    } catch (error) {
      fail(`artifact binding failed: ${error.message}`);
    }
    if (!process.exitCode) console.log("PASS: final acceptance receipt is complete");
  }
}
