const fs = require("node:fs");
const path = require("node:path");

const srcPath = path.join("src", "index.js");
const distDir = "dist";
const distPath = path.join(distDir, "index.js");

fs.mkdirSync(distDir, { recursive: true });
fs.copyFileSync(srcPath, distPath);
console.log("build passed");

