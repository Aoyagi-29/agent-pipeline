import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export type AdbOptions = {
  serial?: string | undefined;
  adbServer?: string | undefined;
};

function adbEnv(adbServer?: string): NodeJS.ProcessEnv {
  if (!adbServer) return process.env;
  return { ...process.env, ADB_SERVER_SOCKET: adbServer };
}

function adbArgs(options: AdbOptions, ...args: string[]): string[] {
  const result: string[] = [];
  if (options.serial) {
    result.push("-s", options.serial);
  }
  result.push(...args);
  return result;
}

async function runAdb(
  options: AdbOptions,
  ...args: string[]
): Promise<{ stdout: string; stderr: string }> {
  const { stdout, stderr } = await execFileAsync(
    "adb",
    adbArgs(options, ...args),
    {
      env: adbEnv(options.adbServer),
      maxBuffer: 20 * 1024 * 1024,
    }
  );
  return { stdout: stdout.trim(), stderr: stderr.trim() };
}

export async function listDevices(
  adbServer?: string
): Promise<Array<{ serial: string; state: string }>> {
  const { stdout } = await runAdb({ adbServer }, "devices", "-l");
  const lines = stdout.split("\n").slice(1);
  const devices: Array<{ serial: string; state: string }> = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const [serial, state] = trimmed.split(/\s+/);
    if (serial && state) {
      devices.push({ serial, state });
    }
  }
  return devices;
}

export async function connectDevice(
  host: string,
  port: number,
  adbServer?: string
): Promise<string> {
  const { stdout } = await runAdb(
    { adbServer },
    "connect",
    `${host}:${port}`
  );
  return stdout;
}

export async function pairDevice(
  host: string,
  port: number,
  pairingCode: string,
  adbServer?: string
): Promise<string> {
  const { stdout } = await runAdb(
    { adbServer },
    "pair",
    `${host}:${port}`,
    pairingCode
  );
  return stdout;
}

export async function disconnectDevice(
  target: string,
  adbServer?: string
): Promise<string> {
  const { stdout } = await runAdb({ adbServer }, "disconnect", target);
  return stdout;
}

export async function shell(
  options: AdbOptions,
  command: string
): Promise<string> {
  const { stdout } = await runAdb(options, "shell", command);
  return stdout;
}

export async function tap(
  options: AdbOptions,
  x: number,
  y: number
): Promise<void> {
  await runAdb(options, "shell", "input", "tap", String(x), String(y));
}

export async function swipe(
  options: AdbOptions,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  durationMs = 300
): Promise<void> {
  await runAdb(
    options,
    "shell",
    "input",
    "swipe",
    String(x1),
    String(y1),
    String(x2),
    String(y2),
    String(durationMs)
  );
}

export async function inputText(
  options: AdbOptions,
  text: string
): Promise<void> {
  const escaped = text.replace(/ /g, "%s").replace(/(['"\\$`!])/g, "\\$1");
  await runAdb(options, "shell", "input", "text", escaped);
}

export async function pressKey(
  options: AdbOptions,
  keycode: string
): Promise<void> {
  await runAdb(options, "shell", "input", "keyevent", keycode);
}

export async function screenshot(
  options: AdbOptions
): Promise<{ mimeType: string; data: string }> {
  const dir = await mkdtemp(join(tmpdir(), "mobile-adb-"));
  const remotePath = "/sdcard/mcp-screenshot.png";
  const localPath = join(dir, "screenshot.png");

  try {
    await runAdb(options, "shell", "screencap", "-p", remotePath);
    await runAdb(options, "pull", remotePath, localPath);
    const buffer = await readFile(localPath);
    return {
      mimeType: "image/png",
      data: buffer.toString("base64"),
    };
  } finally {
    await runAdb(options, "shell", "rm", "-f", remotePath).catch(() => {});
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

export async function dumpUi(options: AdbOptions): Promise<string> {
  const remotePath = "/sdcard/mcp-ui-dump.xml";
  await runAdb(
    options,
    "shell",
    "uiautomator",
    "dump",
    remotePath
  );
  const dir = await mkdtemp(join(tmpdir(), "mobile-adb-"));
  const localPath = join(dir, "ui-dump.xml");

  try {
    await runAdb(options, "pull", remotePath, localPath);
    const xml = await readFile(localPath, "utf8");
    return xml;
  } finally {
    await runAdb(options, "shell", "rm", "-f", remotePath).catch(() => {});
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

export async function getCurrentActivity(options: AdbOptions): Promise<string> {
  const { stdout } = await runAdb(
    options,
    "shell",
    "dumpsys",
    "window",
    "windows"
  );
  const focusLine = stdout
    .split("\n")
    .find((line) => line.includes("mCurrentFocus") || line.includes("mFocusedApp"));
  return focusLine?.trim() ?? "unknown";
}

export async function launchApp(
  options: AdbOptions,
  packageName: string,
  activity?: string
): Promise<void> {
  if (activity) {
    await runAdb(
      options,
      "shell",
      "am",
      "start",
      "-n",
      `${packageName}/${activity}`
    );
    return;
  }
  await runAdb(
    options,
    "shell",
    "monkey",
    "-p",
    packageName,
    "-c",
    "android.intent.category.LAUNCHER",
    "1"
  );
}

export async function writeDebugConfig(
  adbServer: string,
  path: string
): Promise<void> {
  await writeFile(path, JSON.stringify({ adbServer }, null, 2));
}
