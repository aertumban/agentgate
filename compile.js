// Compile AgentGate.sol (+ mock) with solc-js, optimizer on.
// Writes build/<Name>.json with { abi, bytecode, deployedBytecodeSize }.
const fs = require("fs");
const path = require("path");
const solc = require("solc");

const sources = {
  "AgentGate.sol": { content: fs.readFileSync(path.join(__dirname, "contracts/AgentGate.sol"), "utf8") },
  "MockAgentID.sol": { content: fs.readFileSync(path.join(__dirname, "contracts/MockAgentID.sol"), "utf8") },
};

const input = {
  language: "Solidity",
  sources,
  settings: {
    optimizer: { enabled: true, runs: 200 },
    viaIR: true,
    evmVersion: "paris",
    outputSelection: { "*": { "*": ["abi", "evm.bytecode.object", "evm.deployedBytecode.object", "metadata"] } },
  },
};

const out = JSON.parse(solc.compile(JSON.stringify(input)));
if (out.errors) {
  for (const e of out.errors) {
    console.log(e.formattedMessage);
    if (e.severity === "error") process.exitCode = 1;
  }
}
if (process.exitCode) process.exit(1);

fs.mkdirSync(path.join(__dirname, "build"), { recursive: true });
fs.writeFileSync(path.join(__dirname, "build", "standard-json-input.json"), JSON.stringify(input, null, 2));
for (const [file, contracts] of Object.entries(out.contracts)) {
  for (const [name, c] of Object.entries(contracts)) {
    const artifact = {
      contractName: name,
      source: file,
      abi: c.abi,
      metadata: c.metadata,
      bytecode: "0x" + c.evm.bytecode.object,
      deployedSize: (c.evm.deployedBytecode.object.length / 2),
    };
    fs.writeFileSync(path.join(__dirname, "build", name + ".json"), JSON.stringify(artifact, null, 2));
    // rough deploy-gas estimate: 21000 + 32000 create + 200/byte deployed + init exec slack
    const est = 53000 + 200 * artifact.deployedSize + 60000;
    console.log(`${name}: deployed size ${artifact.deployedSize} bytes, rough deploy gas ~${est}`);
  }
}
