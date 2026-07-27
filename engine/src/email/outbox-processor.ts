import fs from "fs";
import path from "path";
import { config } from "../config.js";
import { host } from "../host/index.js";
import { emitApproval } from "../gateway.js";
import { logger } from "../logger.js";
import { uploadAttachment } from "./attachment-uploader.js";
import { consumeEmailPreApproval } from "./pre-approval.js";
import type { Agent, JobData } from "../types.js";
import type { CapturedEmail } from "../tool-interceptor.js";

export interface ApprovalResult {
  approvalId: number;
  to: string;
  subject: string;
  body_text: string;
  // True when this draft surfaced even though the agent has no email
  // channel — agent-runner uses this to append a 'connect email' hint to
  // the user-facing reply so the warning isn't only inside the preview.
  email_not_configured?: boolean;
}

export interface SentResult {
  to: string;
  subject: string;
}

// What the outbox did with this run's drafts. `approvals` still need a human
// decision; `sent` already went out (auto permission, or a draft the human
// pre-approved via request_approval). agent-runner reports both back to the
// user so the reply can't claim "sent" for something still sitting in a card.
export interface OutboxResult {
  approvals: ApprovalResult[];
  sent: SentResult[];
}

// Processes the email outbox after an agent run.
// Combines files written to disk + emails captured from tool calls.
// Routes each email through the permission system: never / draft (approval) / auto (send).
export async function processOutbox(
  agent: Agent,
  job: JobData,
  messageId?: number | null,
  capturedEmails?: CapturedEmail[],
): Promise<OutboxResult> {
  const results: OutboxResult = { approvals: [], sent: [] };

  const channels = await host.getChannelConfigs(String(agent.id));
  const emailConfig = channels.find((c) => c.channel_type === "email");

  const emailsToProcess = collectEmails(capturedEmails);
  if (emailsToProcess.length === 0) return results;

  // When the agent has no email channel configured but drafted email(s),
  // we still create PendingApproval rows so the human can preview what the
  // agent wanted to send. Otherwise the agent's work gets silently dropped
  // — and the user reads 'Drafted email for review' in Slack with no card
  // to actually review. Approvals on this path force permLevel = 'draft'.
  const conversationId = job.conversationId ?? null;

  if (!emailConfig) {
    logger.warn(`No email channel configured — surfacing ${emailsToProcess.length} captured email(s) as draft approval(s) anyway`);
    for (const content of emailsToProcess) {
      try {
        const result = await processOneEmail(content, agent, null, messageId, conversationId);
        if (result?.kind === "approval") results.approvals.push(result.approval);
        if (result?.kind === "sent") results.sent.push(result.sent);
      } catch (err) {
        logger.error(`Failed to surface captured email to ${content.to}`, { error: (err as Error).message });
      }
    }
    return results;
  }

  for (const content of emailsToProcess) {
    try {
      const result = await processOneEmail(content, agent, emailConfig, messageId, conversationId);
      if (result?.kind === "approval") results.approvals.push(result.approval);
      if (result?.kind === "sent") results.sent.push(result.sent);
    } catch (err) {
      logger.error(`Failed to process email to ${content.to}`, { error: (err as Error).message });
    }
  }

  return results;
}

// Combines emails from disk (workspace/outbox/*.json) and captured Write tool calls.
// Deduplicates by to+subject.
function collectEmails(capturedEmails?: CapturedEmail[]): CapturedEmail[] {
  const emails: CapturedEmail[] = [];

  // 1. Read files from disk and delete them
  const outboxDir = path.join(config.dataDir, "workspace", "outbox");
  if (fs.existsSync(outboxDir)) {
    const files = fs.readdirSync(outboxDir).filter((f) => f.endsWith(".json"));
    for (const file of files) {
      const filePath = path.join(outboxDir, file);
      try {
        const content = JSON.parse(fs.readFileSync(filePath, "utf-8")) as CapturedEmail;
        if (content.to) emails.push(content);
        fs.unlinkSync(filePath);
      } catch (err) {
        logger.error(`Failed to read outbox file ${file}`, { error: (err as Error).message });
      }
    }
  }

  // 2. Add captured emails (deduped against disk)
  if (capturedEmails) {
    for (const captured of capturedEmails) {
      const dupe = emails.some((e) => e.to === captured.to && e.subject === captured.subject);
      if (!dupe && captured.to) emails.push(captured);
    }
  }

  return emails;
}

type OneEmailOutcome =
  | { kind: "approval"; approval: ApprovalResult }
  | { kind: "sent"; sent: SentResult }
  | null;

async function processOneEmail(
  content: CapturedEmail,
  agent: Agent,
  emailConfig: { config: Record<string, unknown> } | null,
  messageId?: number | null,
  conversationId?: number | null,
): Promise<OneEmailOutcome> {
  // Upload attachments if specified
  const attachmentIds: string[] = [];
  if (Array.isArray(content.attachments)) {
    for (const relPath of content.attachments) {
      const id = await uploadAttachment(relPath);
      if (id) attachmentIds.push(id);
    }
  }

  const emailPayload = {
    agent_id: agent.id,
    org_id: agent.organization_id,
    conversation_id: conversationId ?? null,
    to: content.to,
    cc: content.cc || [],
    bcc: content.bcc || [],
    subject: content.subject || "(no subject)",
    body_text: content.body_text || "",
    body_html: content.body_html || content.body_text || "",
    from_address: (emailConfig?.config.address as string | undefined) || "(email not configured)",
    from_name: agent.name,
    attachment_ids: attachmentIds,
    email_not_configured: emailConfig == null,
  };

  // Force draft mode when email isn't connected — the message can't be sent
  // anyway, but the user gets to preview what the agent wrote and either
  // connect email + approve, or copy/paste it elsewhere.
  let permLevel = emailConfig == null ? "draft" : (agent.permissions?.["send_email"] || "auto");

  // The human already said yes to this draft on a request_approval card.
  // Raising a second send_email approval here would strand the message: the
  // user approved once, sees "waiting" nowhere, and nothing goes out.
  if (permLevel === "draft" && emailConfig != null) {
    const grant = consumeEmailPreApproval();
    if (grant) {
      logger.info(`Skipping second approval for ${content.to} — already approved (${grant})`);
      permLevel = "auto";
    }
  }

  if (permLevel === "never") {
    logger.info(`Email blocked by permissions: ${content.to}`);
    return null;
  }

  if (permLevel === "draft") {
    const approvalId = await host.savePendingApproval(
      agent.organization_id,
      agent.id,
      "send_email",
      emailPayload,
      `Email to ${content.to}: "${content.subject}"`,
      messageId || undefined,
    );
    emitApproval(approvalId, "send_email", emailPayload);
    logger.info(`Email queued for approval: ${content.to}`);
    return {
      kind: "approval",
      approval: {
        approvalId,
        to: content.to,
        subject: content.subject || "(no subject)",
        body_text: content.body_text || "",
        email_not_configured: emailConfig == null,
      },
    };
  }

  // auto: send immediately via host (Rails enqueues SendEmailJob)
  await host.sendEmail(emailPayload);
  logger.info(`Email sent: ${content.to}`);
  return { kind: "sent", sent: { to: content.to, subject: content.subject || "(no subject)" } };
}
