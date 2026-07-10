#!/usr/bin/env node
// Minimal local HTTP server that receives debug log lines POSTed from the
// LyricsPiP app over the same WiFi network. Useful once the app is in PIP
// mode (screen not visible) or backgrounded, where the on-screen debug
// panel can't be read directly.
//
// Usage: node tools/log-server.mjs [port]
// Then, in the app's debug log panel, set the "remote log server URL" field to
// one of the addresses printed below (e.g. http://192.168.1.5:8787/log).

import http from "node:http";
import os from "node:os";

const port = Number(process.argv[2]) || 8787;

function localIPs() {
  const nets = os.networkInterfaces();
  const results = [];
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] ?? []) {
      if (net.family === "IPv4" && !net.internal) results.push(net.address);
    }
  }
  return results;
}

const server = http.createServer((req, res) => {
  if (req.method === "POST" && req.url === "/log") {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
    });
    req.on("end", () => {
      const timestamp = new Date().toISOString().slice(11, 23);
      console.log(`[recv ${timestamp}] ${body}`);
      res.writeHead(204);
      res.end();
    });
    return;
  }
  res.writeHead(404);
  res.end();
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Log server listening on port ${port}`);
  console.log("Point the app's debug log panel at one of:");
  for (const ip of localIPs()) {
    console.log(`  http://${ip}:${port}/log`);
  }
});
