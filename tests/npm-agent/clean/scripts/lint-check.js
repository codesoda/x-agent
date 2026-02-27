const fs = require("node:fs");

const src = fs.readFileSync("src/index.js", "utf8");
if (src.includes("var ")) {
  console.error("lint check failed: do not use var");
  process.exit(1);
}

console.log("lint check passed");

