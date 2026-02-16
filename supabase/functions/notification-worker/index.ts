import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

type Channel = "push" | "email";

type QueueJob = {
  id: string;
  profile_id: string;
  hall_id: string;
  tournament_id: string | null;
  channel: Channel;
  kind: string;
  title: string;
  body: string;
  payload: Record<string, unknown> | null;
};

type ProcessResult = {
  channel: Channel;
  claimed: number;
  sent: number;
  failed: number;
  failures: Array<{ id: string; error: string }>;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const RESEND_FROM_EMAIL = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
const WORKER_SECRET = Deno.env.get("WORKER_SECRET") ?? "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function toErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.max(min, Math.min(max, value));
}

async function claimJobs(channel: Channel, limit: number): Promise<QueueJob[]> {
  const { data, error } = await supabase.rpc("claim_notification_queue_jobs", {
    p_channel: channel,
    p_limit: limit,
  });

  if (error) throw error;
  return (data ?? []) as QueueJob[];
}

async function markJob(id: string, success: boolean, errorText?: string) {
  const { error } = await supabase.rpc("mark_notification_queue_job", {
    p_id: id,
    p_success: success,
    p_error: errorText ?? null,
  });
  if (error) throw error;
}

async function fetchProfileEmail(profileId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from("profiles")
    .select("email")
    .eq("id", profileId)
    .maybeSingle();

  if (error) throw error;
  const email = (data?.email ?? "").toString().trim();
  return email.isEmpty ? null : email;
}

async function fetchPushTokens(profileId: string): Promise<string[]> {
  const { data, error } = await supabase
    .from("profile_push_tokens")
    .select("expo_push_token")
    .eq("profile_id", profileId)
    .eq("is_active", true);

  if (error) throw error;

  const tokens: string[] = [];
  for (const row of (data ?? []) as Array<{ expo_push_token?: string }>) {
    const token = (row.expo_push_token ?? "").trim();
    if (token) tokens.push(token);
  }
  return tokens;
}

async function sendEmailWithResend(job: QueueJob, toEmail: string) {
  if (!RESEND_API_KEY || !RESEND_FROM_EMAIL) {
    throw new Error("RESEND is not configured");
  }

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: RESEND_FROM_EMAIL,
      to: [toEmail],
      subject: job.title,
      text: job.body,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Resend error ${response.status}: ${text}`);
  }
}

async function sendPushWithExpo(job: QueueJob, tokens: string[]) {
  if (tokens.length == 0) {
    throw new Error("No active push tokens");
  }

  const messages = tokens.map((token) => ({
    to: token,
    title: job.title,
    body: job.body,
    data: job.payload ?? {},
    sound: "default",
  }));

  const response = await fetch("https://exp.host/--/api/v2/push/send", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(messages),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Expo Push error ${response.status}: ${text}`);
  }

  const result = await response.json();
  const tickets = Array.isArray(result?.data) ? result.data : [];
  const failed = tickets.find((t: Record<string, unknown>) => t?.status === "error");
  if (failed) {
    throw new Error(`Expo ticket error: ${JSON.stringify(failed)}`);
  }
}

async function processChannel(
  channel: Channel,
  limit: number,
  dryRun: boolean,
): Promise<ProcessResult> {
  const jobs = await claimJobs(channel, limit);

  const result: ProcessResult = {
    channel,
    claimed: jobs.length,
    sent: 0,
    failed: 0,
    failures: [],
  };

  for (const job of jobs) {
    try {
      if (channel === "email") {
        const email = await fetchProfileEmail(job.profile_id);
        if (!email) throw new Error("Profile email is empty");
        if (!dryRun) await sendEmailWithResend(job, email);
      } else {
        const tokens = await fetchPushTokens(job.profile_id);
        if (!dryRun) await sendPushWithExpo(job, tokens);
      }

      if (!dryRun) {
        await markJob(job.id, true);
      }
      result.sent += 1;
    } catch (error) {
      const message = toErrorMessage(error);
      if (!dryRun) {
        try {
          await markJob(job.id, false, message);
        } catch (markError) {
          console.error("mark failed job error:", markError);
        }
      }
      result.failed += 1;
      result.failures.push({ id: job.id, error: message });
      console.error(`job ${job.id} failed:`, message);
    }
  }

  return result;
}

function ensureAuthorized(req: Request): boolean {
  if (!WORKER_SECRET) return true;
  const secret = req.headers.get("x-worker-secret") ?? "";
  return secret === WORKER_SECRET;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Use POST" });
  }

  if (!ensureAuthorized(req)) {
    return json(401, { ok: false, error: "Unauthorized" });
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    // empty body is acceptable
  }

  const rawChannels = Array.isArray(body.channels)
    ? body.channels
    : ["push", "email"];
  const channels = rawChannels.filter((c): c is Channel =>
    c === "push" || c === "email"
  );

  if (channels.length === 0) {
    return json(400, { ok: false, error: "No valid channels provided" });
  }

  const limit = clamp(Number(body.limit ?? 50), 1, 500);
  const dryRun = Boolean(body.dry_run ?? false);

  const summaries: ProcessResult[] = [];
  for (const channel of channels) {
    try {
      const summary = await processChannel(channel, limit, dryRun);
      summaries.push(summary);
    } catch (error) {
      const message = toErrorMessage(error);
      summaries.push({
        channel,
        claimed: 0,
        sent: 0,
        failed: 0,
        failures: [{ id: "channel_error", error: message }],
      });
      console.error(`channel ${channel} failed:`, message);
    }
  }

  const totalClaimed = summaries.reduce((acc, s) => acc + s.claimed, 0);
  const totalSent = summaries.reduce((acc, s) => acc + s.sent, 0);
  const totalFailed = summaries.reduce((acc, s) => acc + s.failed, 0);

  return json(200, {
    ok: true,
    dry_run: dryRun,
    limit,
    channels,
    totals: {
      claimed: totalClaimed,
      sent: totalSent,
      failed: totalFailed,
    },
    summaries,
  });
});
