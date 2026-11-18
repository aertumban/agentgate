// Local EVM tests for AgentGate against a MockAgentID registry (ganache).
const assert = require("assert");
const ganache = require("ganache");
const { ethers } = require("ethers");
const fs = require("fs");

const gateArt = JSON.parse(fs.readFileSync(__dirname + "/build/AgentGate.json", "utf8"));
const mockArt = JSON.parse(fs.readFileSync(__dirname + "/build/MockAgentID.json", "utf8"));

async function expectRevert(promise, needle) {
  try {
    const tx = await promise;
    if (tx && typeof tx.wait === "function") {
      const receipt = await tx.wait();
      if (receipt && receipt.status === 0) return; // mined but reverted
    }
  } catch (e) {
    const msg = (e.message || "") + (e.data || "");
    assert(msg.includes(needle) || e.code === "CALL_EXCEPTION" || msg.includes("revert"), `revert without '${needle}': ${msg.slice(0, 200)}`);
    return;
  }
  throw new Error(`expected revert (${needle}) but call succeeded`);
}

(async () => {
  const provider = new ethers.BrowserProvider(ganache.provider());
  const [deployer, alice, bob, carol] = await Promise.all([0, 1, 2, 3].map((i) => provider.getSigner(i)));

  // --- deploy mock registry + gate ---
  const mock = await new ethers.ContractFactory(mockArt.abi, mockArt.bytecode, deployer).deploy();
  await mock.waitForDeployment();
  await mock.setHolder(await alice.getAddress(), 1);
  await mock.setHolder(await bob.getAddress(), 1);

  const gate = await new ethers.ContractFactory(gateArt.abi, gateArt.bytecode, deployer).deploy(await mock.getAddress());
  await gate.waitForDeployment();
  console.log("deployed gate:", await gate.getAddress());

  const A = await alice.getAddress(), B = await bob.getAddress(), C = await carol.getAddress();
  assert.equal(await gate.isAgentIdHolder(A), true);
  assert.equal(await gate.isAgentIdHolder(C), false);

  // --- non-holder cannot claim ---
  await expectRevert(gate.connect(carol).claimBadge(ethers.ZeroAddress), "NotAgentIdHolder");
  console.log("ok: non-holder claim reverts");

  // --- self-invite reverts ---
  await expectRevert(gate.connect(alice).claimBadge(A), "SelfInvite");
  console.log("ok: self-invite reverts");

  // --- alice claims badge #1 ---
  await (await gate.connect(alice).claimBadge(ethers.ZeroAddress)).wait();
  assert.equal(await gate.badgeOf(A), 1n);
  assert.equal(await gate.ownerOf(1), A);
  assert.equal(await gate.balanceOf(A), 1n);
  console.log("ok: alice claimed badge #1");

  // --- double claim reverts ---
  await expectRevert(gate.connect(alice).claimBadge(ethers.ZeroAddress), "BadgeAlreadyClaimed");
  console.log("ok: double claim reverts");

  // --- soulbound: transfer + approve revert ---
  await expectRevert(gate.connect(alice).transferFrom(A, B, 1), "Soulbound");
  await expectRevert(gate.connect(alice).approve(B, 1), "Soulbound");
  console.log("ok: badge is soulbound");

  // --- check-in day 0, streak 1; same-day again reverts ---
  await (await gate.connect(alice).checkIn()).wait();
  let p = await gate.profileOf(A);
  assert.equal(p.streak, 1n); assert.equal(p.checkIns, 1n);
  await expectRevert(gate.connect(alice).checkIn(), "AlreadyCheckedInToday");
  console.log("ok: check-in + same-day revert");

  // --- +1 day: streak 2 ---
  await provider.send("evm_increaseTime", [86400]);
  await provider.send("evm_mine", []);
  await (await gate.connect(alice).checkIn()).wait();
  p = await gate.profileOf(A);
  assert.equal(p.streak, 2n); assert.equal(p.bestStreak, 2n);
  console.log("ok: next-day check-in, streak 2");

  // --- skip a day (+2 days): streak resets to 1, best stays 2 ---
  await provider.send("evm_increaseTime", [2 * 86400]);
  await provider.send("evm_mine", []);
  await (await gate.connect(alice).checkIn()).wait();
  p = await gate.profileOf(A);
  assert.equal(p.streak, 1n); assert.equal(p.bestStreak, 2n); assert.equal(p.checkIns, 3n);
  console.log("ok: skipped day resets streak, best kept");

  // --- bob claims with inviter = alice ---
  await (await gate.connect(bob).claimBadge(A)).wait();
  assert.equal(await gate.badgeOf(B), 2n);
  assert.equal(await gate.inviterOf(B), A);
  console.log("ok: bob claimed badge #2, inviter recorded");

  // --- carol (no badge) check-in reverts ---
  await expectRevert(gate.connect(carol).checkIn(), "NoBadge");
  console.log("ok: check-in without badge reverts");

  // --- gate is live: revoke alice's Agent ID -> check-in reverts ---
  await mock.setHolder(A, 0);
  await expectRevert(gate.connect(alice).checkIn(), "NotAgentIdHolder");
  await mock.setHolder(A, 1);
  console.log("ok: losing the Agent ID blocks check-in (live gate)");

  // --- stats + tokenURI ---
  const s = await gate.stats();
  assert.equal(s.badges, 2n); assert.equal(s.checkIns, 3n);
  const uri = await gate.tokenURI(1);
  const json = JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString());
  assert.equal(json.name, "AgentGate Badge #1");
  assert.equal(json.attributes.find((a) => a.trait_type === "Total check-ins").value, 3);
  console.log("ok: stats + dynamic tokenURI:", JSON.stringify(json.attributes));

  // --- ERC165 ---
  assert.equal(await gate.supportsInterface("0x80ac58cd"), true);
  console.log("ok: supportsInterface ERC721");

  console.log("\nALL TESTS PASSED");
  process.exit(0);
})().catch((e) => { console.error("TEST FAILURE:", e); process.exit(1); });
