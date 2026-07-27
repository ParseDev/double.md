// Run-scoped record that a human ALREADY approved an email the agent is
// about to write to the outbox.
//
// Without this, an agent that asks via `request_approval({payload_type:
// "email_draft"})` and gets a "yes" then hits the outbox processor, which
// sees permissions.send_email === "draft" and raises a SECOND send_email
// approval for the very same message. The user approved once, nothing was
// sent, and the second card sits unnoticed — the agent meanwhile reports
// "Email sent". That double-ask is the bug this file exists to prevent.
//
// A grant lands here two ways:
//   1. In-run — request_approval resolved with an approve-ish decision
//      during this same turn (tools/approvals.ts).
//   2. Resumed run — the user decided after the turn released its wait;
//      Rails wakes the agent with approvalPayloadType + approvalDecision on
//      the job payload and agent-runner replays the grant.
//
// One grant covers one email. consume() clears it, so a second (unapproved)
// email drafted in the same run still goes through the normal permission
// check.

import { logger } from "../logger.js";

// Decision values that mean "don't send" — everything else on an email
// approval card is treated as consent (options are agent-authored, so we
// can't enumerate the yes-side).
const NON_APPROVING = new Set(["reject", "rejected", "cancel", "cancelled", "deny", "denied", "no", "edit", "amend", "pending"]);

const grants: string[] = [];

export function isApprovingDecision(value: string | undefined | null): boolean {
  if (!value) return false;
  return !NON_APPROVING.has(String(value).trim().toLowerCase());
}

// Records that the human okayed an email draft. `reason` is logged so the
// audit trail explains why the outbox skipped the permission gate. `count`
// is >1 for bulk cards, where one "yes" covers every email in the batch.
export function markEmailPreApproved(reason: string, count = 1): void {
  for (let i = 0; i < Math.max(1, count); i++) grants.push(reason);
  logger.info(`Email pre-approved by human (${Math.max(1, count)}): ${reason}`);
}

// Takes one grant if any is available. Returns the reason string (for logs)
// or null when the email still needs the normal approval flow.
export function consumeEmailPreApproval(): string | null {
  return grants.shift() ?? null;
}

// Called at the top of every run so a grant that was never consumed (agent
// changed its mind and drafted nothing) can't leak into a later, unrelated
// turn.
export function clearEmailPreApprovals(): void {
  grants.length = 0;
}
