import { mkdirSync, writeFileSync, renameSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

// Une pastille par processus OMP principal, meme apres /new ou /resume.
// L'etat reste propre a chaque factory : OMP les reutilise pour ses sous-agents.
export default function (pi: ExtensionAPI) {
    const base = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
    const dossier = join(base, "codex-feu-rouge");
    const fichier = join(dossier, `omp-pid-${process.pid}.json`);
    const temporaire = `${fichier}.tmp`;
    const attentes = new Set<string>();
    let actif = false;
    let ferme = false;

    function ecrire(ctx: ExtensionContext) {
        if (ctx.agent.kind !== "main" || ferme) return;

        let state = "idle";
        if (actif) state = "running";
        if (attentes.size > 0) state = "waiting";

        try {
            mkdirSync(dossier, { recursive: true });
            const contenu = {
                state,
                agent: "omp",
                cwd: ctx.cwd,
                pid: process.pid,
                ts: Math.floor(Date.now() / 1000),
            };
            writeFileSync(temporaire, JSON.stringify(contenu) + "\n");
            renameSync(temporaire, fichier);
        } catch {
            // Une erreur de barre de menus ne doit pas interrompre l'agent.
        }
    }

    function demarrer(_event: unknown, ctx: ExtensionContext) {
        if (ctx.agent.kind !== "main") return;
        ferme = false;
        actif = !ctx.isIdle();
        attentes.clear();
        ecrire(ctx);
    }

    pi.on("session_start", demarrer);
    pi.on("session_switch", demarrer);
    pi.on("session_branch", demarrer);
    pi.on("agent_start", (_event, ctx) => {
        if (ctx.agent.kind !== "main") return;
        actif = true;
        ecrire(ctx);
    });
    pi.on("agent_end", (_event, ctx) => {
        if (ctx.agent.kind !== "main") return;
        actif = false;
        ecrire(ctx);
    });

    pi.on("tool_approval_requested", (event, ctx) => {
        if (ctx.agent.kind !== "main") return;
        attentes.add(`approval-${event.toolCallId}`);
        ecrire(ctx);
    });
    pi.on("tool_approval_resolved", (event, ctx) => {
        if (ctx.agent.kind !== "main") return;
        attentes.delete(`approval-${event.toolCallId}`);
        ecrire(ctx);
    });
    pi.on("plan_review_requested", (event, ctx) => {
        if (ctx.agent.kind !== "main") return;
        attentes.add(`plan-${event.reviewId}`);
        ecrire(ctx);
    });
    pi.on("plan_review_resolved", (event, ctx) => {
        if (ctx.agent.kind !== "main") return;
        attentes.delete(`plan-${event.reviewId}`);
        ecrire(ctx);
    });
    pi.on("tool_execution_start", (event, ctx) => {
        if (ctx.agent.kind !== "main") return;
        if (event.toolName === "ask") {
            attentes.add(`ask-${event.toolCallId}`);
            ecrire(ctx);
        }
    });
    pi.on("tool_execution_end", (event, ctx) => {
        if (ctx.agent.kind !== "main") return;
        if (event.toolName === "ask") {
            attentes.delete(`ask-${event.toolCallId}`);
            ecrire(ctx);
        }
    });
    pi.on("session_shutdown", (_event, ctx) => {
        if (ctx.agent.kind !== "main") return;
        ferme = true;
        try {
            rmSync(fichier, { force: true });
            rmSync(temporaire, { force: true });
        } catch {
            // L'app nettoie aussi le fichier lorsque le processus disparait.
        }
    });
}
