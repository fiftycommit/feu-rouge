// Executer avec Node >= 24 : node tests/omp-extension.mjs
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import feuRouge from "../extensions/feu-rouge.ts";

const dossier = mkdtempSync(join(tmpdir(), "feu-rouge-test-"));
const ancien = process.env.XDG_STATE_HOME;
process.env.XDG_STATE_HOME = dossier;

try {
    const handlers = new Map();
    feuRouge({ on(event, handler) { handlers.set(event, handler); } });
    const ctx = { cwd: '/projets/test "accentué"', agent: { kind: "main" }, isIdle: () => true };
    const fichier = join(dossier, "codex-feu-rouge", `omp-pid-${process.pid}.json`);
    function emit(event, payload = {}, context = ctx) {
        handlers.get(event)(payload, context);
    }
    function verifier(state) {
        const contenu = JSON.parse(readFileSync(fichier, "utf8"));
        assert.equal(contenu.state, state);
        assert.equal(contenu.agent, "omp");
        assert.equal(contenu.pid, process.pid);
        assert.equal(contenu.cwd, ctx.cwd);
    }

    emit("session_start");
    verifier("idle");
    emit("agent_start");
    verifier("running");
    emit("tool_approval_requested", { toolCallId: "a" });
    emit("tool_approval_requested", { toolCallId: "b" });
    verifier("waiting");
    emit("tool_approval_resolved", { toolCallId: "a" });
    verifier("waiting");
    emit("tool_approval_resolved", { toolCallId: "b" });
    verifier("running");
    emit("plan_review_requested", { reviewId: "plan" });
    emit("agent_end");
    verifier("waiting");
    emit("plan_review_resolved", { reviewId: "plan" });
    verifier("idle");
    emit("agent_start");
    emit("tool_execution_start", { toolName: "ask", toolCallId: "question" });
    verifier("waiting");
    emit("tool_execution_end", { toolName: "ask", toolCallId: "question" });
    verifier("running");

    // Les evenements d'un conseiller ne changent pas l'etat du principal.
    const sub = { ...ctx, agent: { kind: "sub" } };
    emit("agent_end", {}, sub);
    emit("tool_approval_requested", { toolCallId: "sub" }, sub);
    emit("session_shutdown", {}, sub);
    verifier("running");
    emit("agent_end");
    verifier("idle");

    ctx.cwd = "/projets/autre";
    emit("session_switch");
    verifier("idle");
    emit("session_branch");
    verifier("idle");
    emit("session_shutdown");
    assert.equal(existsSync(fichier), false);
    emit("agent_end");
    assert.equal(existsSync(fichier), false);
    console.log("OK : cycle OMP, attentes simultanees, sous-agents, changement de session et fermeture");
} finally {
    if (ancien === undefined) delete process.env.XDG_STATE_HOME;
    else process.env.XDG_STATE_HOME = ancien;
    rmSync(dossier, { recursive: true, force: true });
}
