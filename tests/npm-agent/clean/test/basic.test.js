const test = require("node:test");
const assert = require("node:assert/strict");
const { sum } = require("../src/index");

test("sum adds values", () => {
  assert.equal(sum(2, 3), 5);
});

