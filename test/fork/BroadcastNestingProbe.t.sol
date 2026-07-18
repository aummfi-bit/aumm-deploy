// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";

/// @title  ProbeTarget
/// @notice Minimal deployment target for the PB3.4d1 nesting probe — records its CREATE sender and the
///         sender of an in-broadcast call, and carries a deployer-gated one-shot mirroring the PB-D23 (i)
///         direct-governor CCB-seal mechanic.
contract ProbeTarget {
    address public immutable deployer;
    address public lastCaller;
    bool public sealedOnce;

    error NotDeployer(address expected, address actual);
    error AlreadySealed();

    constructor() {
        deployer = msg.sender;
    }

    function mark() external {
        lastCaller = msg.sender;
    }

    /// @notice One-shot gated on the CREATE sender — lands only if broadcast attribution rewrote the
    ///         constructor msg.sender to the governor (PB-D23 (i)).
    function sealOnce() external {
        if (msg.sender != deployer) revert NotDeployer(deployer, msg.sender);
        if (sealedOnce) revert AlreadySealed();
        sealedOnce = true;
    }
}

/// @title  ProbeSubScript
/// @notice Depth-2 broadcaster — mirrors the PB3.4b sub-script run() shape: env-read governor,
///         self-broadcast, CREATE and call under the broadcast, PB-D24 (ii) public-storage handle.
contract ProbeSubScript is Script {
    ProbeTarget public target;

    function run() external {
        address governor = vm.envAddress("PROBE_GOVERNOR");
        vm.startBroadcast(governor);
        target = new ProbeTarget();
        target.mark();
        vm.stopBroadcast();
    }
}

/// @title  ProbeOrchestrator
/// @notice Depth-1 composer — mirrors _orchestrateProduction: two sub-run()s with the orchestrator's
///         own broadcast block between them, that block firing a deployer-gated one-shot at a contract
///         CREATEd under the FIRST sub's broadcast (the PB-D23 (i) dual-path seal mechanic), handles
///         captured from sub public storage per PB-D24 (ii).
contract ProbeOrchestrator is Script {
    ProbeSubScript public subA;
    ProbeSubScript public subB;

    function run() external {
        address governor = vm.envAddress("PROBE_GOVERNOR");

        subA = new ProbeSubScript();
        subA.run();

        ProbeTarget targetA = subA.target();
        vm.startBroadcast(governor);
        targetA.sealOnce();
        vm.stopBroadcast();

        subB = new ProbeSubScript();
        subB.run();
    }
}

/// @title  BroadcastNestingProbeTest
/// @notice PB3.4d1 — the PB-D23 (v) RUNG 1 G10-class nesting probe. Depth-2 vm.startBroadcast through
///         composed run() entries has no in-tree precedent (the fixtures nest one level only), so this
///         probe pins the mechanics the PB3.4d rehearsal harness depends on BEFORE the harness shape
///         commits: (1) run() composes without a cheatcode revert; (2) CREATE and CALL sender
///         attribution under a depth-2 broadcast is the env governor; (3) the orchestrator's own
///         broadcast blocks interleave with sub-run()s without collision, including the deployer-gated
///         one-shot on a contract CREATEd under a sub's broadcast; (4) no broadcast state leaks past
///         run(). Fallback if this probe fails: the harness drives the sub-run() sequence around a
///         forge-script-invoked fork dry-run per PB-D23 (v), user-run under section 8b.
/// @dev    Run file-scoped per D35/D36: forge test with match-path on this file, fork-url mainnet,
///         threads 1. Uses a probe-scoped env key (PROBE_GOVERNOR), never the real GOVERNANCE_MULTISIG.
contract BroadcastNestingProbeTest is Test {
    function test_DepthTwoBroadcast_ComposedRunSenderAttribution() external {
        address governor = address(0xA11CE);
        vm.setEnv("PROBE_GOVERNOR", vm.toString(governor));

        ProbeOrchestrator orchestrator = new ProbeOrchestrator();
        orchestrator.run();

        // (2) depth-2 CREATE and CALL sender attribution under subA's own broadcast.
        ProbeSubScript subA = orchestrator.subA();
        ProbeTarget targetA = subA.target();
        assertEq(targetA.deployer(), governor, "subA CREATE sender is not the governor");
        assertEq(targetA.lastCaller(), governor, "subA in-broadcast call sender is not the governor");

        // (3) the orchestrator's own interleaved block landed the deployer-gated one-shot as the governor.
        assertTrue(targetA.sealedOnce(), "orchestrator direct-governor one-shot did not land");

        // (3) serialization: the second sub-run() broadcast opened cleanly after the orchestrator's block.
        ProbeSubScript subB = orchestrator.subB();
        ProbeTarget targetB = subB.target();
        assertEq(targetB.deployer(), governor, "subB CREATE sender is not the governor");
        assertEq(targetB.lastCaller(), governor, "subB in-broadcast call sender is not the governor");

        // (4) no dangling broadcast: a post-run() call from the test carries the test contract as sender.
        targetA.mark();
        assertEq(targetA.lastCaller(), address(this), "broadcast leaked past orchestrator.run()");
    }
}
