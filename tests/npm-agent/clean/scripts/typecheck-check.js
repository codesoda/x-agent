const { sum } = require("../src/index");

if (sum(1, 2) !== 3) {
  console.error("typecheck guard failed");
  process.exit(1);
}

console.log("typecheck check passed");

