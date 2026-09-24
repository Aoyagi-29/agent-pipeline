#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as adb from "./adb.js";

const adbServer = process.env.ADB_SERVER_SOCKET;
const defaultSerial = process.env.ADB_SERIAL;

function deviceOptions(serial?: string): adb.AdbOptions {
  const opts: adb.AdbOptions = {};
  const s = serial ?? defaultSerial;
  if (s) opts.serial = s;
  if (adbServer) opts.adbServer = adbServer;
  return opts;
}

const server = new McpServer({
  name: "mobile-adb",
  version: "1.0.0",
});

server.registerTool(
  "mobile_list_devices",
  {
    description:
      "List Android devices connected to ADB. Use before other mobile tools to confirm connectivity.",
    inputSchema: {},
  },
  async () => {
    const devices = await adb.listDevices(adbServer);
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({ devices, adbServer: adbServer ?? "local" }, null, 2),
        },
      ],
    };
  }
);

server.registerTool(
  "mobile_connect",
  {
    description:
      "Connect to an Android device over wireless debugging (adb connect). Requires the phone IP and port.",
    inputSchema: {
      host: z.string().describe("Phone IP address or hostname"),
      port: z.number().int().default(5555).describe("Wireless debugging port"),
    },
  },
  async ({ host, port }) => {
    const result = await adb.connectDevice(host, port, adbServer);
    return { content: [{ type: "text", text: result }] };
  }
);

server.registerTool(
  "mobile_pair",
  {
    description:
      "Pair with an Android device for wireless debugging (Android 11+). Use the pairing port and 6-digit code shown on the phone.",
    inputSchema: {
      host: z.string().describe("Phone IP address or hostname"),
      port: z.number().int().describe("Pairing port (not the connect port)"),
      pairingCode: z.string().describe("6-digit pairing code from the phone"),
    },
  },
  async ({ host, port, pairingCode }) => {
    const result = await adb.pairDevice(host, port, pairingCode, adbServer);
    return { content: [{ type: "text", text: result }] };
  }
);

server.registerTool(
  "mobile_screenshot",
  {
    description: "Capture a screenshot from the connected Android device.",
    inputSchema: {
      serial: z.string().optional().describe("Device serial (optional if only one device)"),
    },
  },
  async ({ serial }) => {
    const shot = await adb.screenshot(deviceOptions(serial));
    return {
      content: [
        { type: "text", text: "Screenshot captured." },
        { type: "image", data: shot.data, mimeType: shot.mimeType },
      ],
    };
  }
);

server.registerTool(
  "mobile_tap",
  {
    description: "Tap at screen coordinates (x, y) on the Android device.",
    inputSchema: {
      x: z.number().int(),
      y: z.number().int(),
      serial: z.string().optional(),
    },
  },
  async ({ x, y, serial }) => {
    await adb.tap(deviceOptions(serial), x, y);
    return {
      content: [{ type: "text", text: `Tapped at (${x}, ${y})` }],
    };
  }
);

server.registerTool(
  "mobile_swipe",
  {
    description: "Swipe on the Android device from (x1,y1) to (x2,y2).",
    inputSchema: {
      x1: z.number().int(),
      y1: z.number().int(),
      x2: z.number().int(),
      y2: z.number().int(),
      durationMs: z.number().int().default(300),
      serial: z.string().optional(),
    },
  },
  async ({ x1, y1, x2, y2, durationMs, serial }) => {
    await adb.swipe(deviceOptions(serial), x1, y1, x2, y2, durationMs);
    return {
      content: [
        {
          type: "text",
          text: `Swiped from (${x1}, ${y1}) to (${x2}, ${y2}) in ${durationMs}ms`,
        },
      ],
    };
  }
);

server.registerTool(
  "mobile_input_text",
  {
    description: "Type text on the Android device (focused input field). Spaces become %s.",
    inputSchema: {
      text: z.string(),
      serial: z.string().optional(),
    },
  },
  async ({ text, serial }) => {
    await adb.inputText(deviceOptions(serial), text);
    return { content: [{ type: "text", text: `Typed: ${text}` }] };
  }
);

server.registerTool(
  "mobile_press_key",
  {
    description:
      "Press an Android key. Common keycodes: HOME=3, BACK=4, ENTER=66, VOLUME_UP=24, VOLUME_DOWN=25, POWER=26.",
    inputSchema: {
      keycode: z.string().describe("Android keyevent code or name"),
      serial: z.string().optional(),
    },
  },
  async ({ keycode, serial }) => {
    await adb.pressKey(deviceOptions(serial), keycode);
    return { content: [{ type: "text", text: `Pressed key: ${keycode}` }] };
  }
);

server.registerTool(
  "mobile_shell",
  {
    description: "Run a shell command on the Android device via adb shell.",
    inputSchema: {
      command: z.string(),
      serial: z.string().optional(),
    },
  },
  async ({ command, serial }) => {
    const output = await adb.shell(deviceOptions(serial), command);
    return { content: [{ type: "text", text: output || "(no output)" }] };
  }
);

server.registerTool(
  "mobile_dump_ui",
  {
    description:
      "Dump the UI hierarchy (uiautomator) as XML. Useful for finding element bounds before tapping.",
    inputSchema: {
      serial: z.string().optional(),
    },
  },
  async ({ serial }) => {
    const xml = await adb.dumpUi(deviceOptions(serial));
    const truncated =
      xml.length > 120_000 ? `${xml.slice(0, 120_000)}\n... (truncated)` : xml;
    return { content: [{ type: "text", text: truncated }] };
  }
);

server.registerTool(
  "mobile_current_activity",
  {
    description: "Get the currently focused app/activity on the device.",
    inputSchema: {
      serial: z.string().optional(),
    },
  },
  async ({ serial }) => {
    const activity = await adb.getCurrentActivity(deviceOptions(serial));
    return { content: [{ type: "text", text: activity }] };
  }
);

server.registerTool(
  "mobile_launch_app",
  {
    description: "Launch an Android app by package name (and optional activity).",
    inputSchema: {
      packageName: z.string(),
      activity: z.string().optional(),
      serial: z.string().optional(),
    },
  },
  async ({ packageName, activity, serial }) => {
    await adb.launchApp(deviceOptions(serial), packageName, activity);
    return {
      content: [{ type: "text", text: `Launched ${packageName}` }],
    };
  }
);

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
