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

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

type FcmTokenCache = {
  accessToken: string;
  projectId: string;
  expiresAtMs: number;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const RESEND_FROM_EMAIL = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
const WORKER_SECRET = Deno.env.get("WORKER_SECRET") ?? "";
const FCM_SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

let fcmTokenCache: FcmTokenCache | null = null;
const textEncoder = new TextEncoder();

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

function bytesToBinary(bytes: Uint8Array): string {
  let result = "";
  for (const byte of bytes) {
    result += String.fromCharCode(byte);
  }
  return result;
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  return btoa(bytesToBinary(bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64UrlEncodeString(value: string): string {
  return base64UrlEncodeBytes(textEncoder.encode(value));
}

function pemToDer(pem: string): Uint8Array {
  const normalized = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function readFcmServiceAccount(): FirebaseServiceAccount {
  const raw = FCM_SERVICE_ACCOUNT_JSON.trim();
  if (!raw) {
    throw new Error("FCM_SERVICE_ACCOUNT_JSON is not configured");
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(raw) as Record<string, unknown>;
  } catch (error) {
    throw new Error(`FCM_SERVICE_ACCOUNT_JSON parse failed: ${toErrorMessage(error)}`);
  }

  const serviceAccount: FirebaseServiceAccount = {
    project_id: (parsed.project_id ?? "").toString().trim(),
    client_email: (parsed.client_email ?? "").toString().trim(),
    private_key: (parsed.private_key ?? "").toString().replace(/\\n/g, "\n").trim(),
    token_uri: (parsed.token_uri ?? "https://oauth2.googleapis.com/token").toString().trim(),
  };

  if (!serviceAccount.project_id || !serviceAccount.client_email || !serviceAccount.private_key) {
    throw new Error("FCM service account must include project_id, client_email, private_key");
  }

  return serviceAccount;
}

async function createServiceAccountJwt(serviceAccount: FirebaseServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    iat: now,
    exp: now + 3600,
  };

  const encodedHeader = base64UrlEncodeString(JSON.stringify(header));
  const encodedPayload = base64UrlEncodeString(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signatureBuffer = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    textEncoder.encode(signingInput),
  );
  const signature = new Uint8Array(signatureBuffer);
  return `${signingInput}.${base64UrlEncodeBytes(signature)}`;
}

async function getFcmAccessToken(): Promise<{ accessToken: string; projectId: string }> {
  if (fcmTokenCache && Date.now() < fcmTokenCache.expiresAtMs - 60_000) {
    return {
      accessToken: fcmTokenCache.accessToken,
      projectId: fcmTokenCache.projectId,
    };
  }

  const serviceAccount = readFcmServiceAccount();
  const assertion = await createServiceAccountJwt(serviceAccount);

  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });

  const response = await fetch(serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`FCM OAuth error ${response.status}: ${text}`);
  }

  const data = await response.json() as Record<string, unknown>;
  const accessToken = (data.access_token ?? "").toString().trim();
  const expiresIn = Number(data.expires_in ?? 3600);
  if (!accessToken) {
    throw new Error("FCM OAuth token response does not contain access_token");
  }

  const safeExpiresIn = Number.isFinite(expiresIn) ? Math.max(60, expiresIn) : 3600;
  fcmTokenCache = {
    accessToken,
    projectId: serviceAccount.project_id,
    expiresAtMs: Date.now() + safeExpiresIn * 1000,
  };

  return { accessToken, projectId: serviceAccount.project_id };
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
  return email.length === 0 ? null : email;
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

async function deactivatePushToken(token: string) {
  const { error } = await supabase
    .from("profile_push_tokens")
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq("expo_push_token", token);

  if (error) {
    console.error(`failed to deactivate token ${token.slice(0, 12)}...:`, error);
  }
}

function buildFcmData(job: QueueJob): Record<string, string> {
  const data: Record<string, string> = {
    kind: job.kind,
    hall_id: job.hall_id,
  };

  if (job.tournament_id) {
    data.tournament_id = job.tournament_id;
  }

  for (const [key, value] of Object.entries(job.payload ?? {})) {
    const normalizedKey = key.trim();
    if (!normalizedKey || value === null || value === undefined) continue;

    if (typeof value === "string") {
      data[normalizedKey] = value;
      continue;
    }

    if (typeof value === "number" || typeof value === "boolean") {
      data[normalizedKey] = String(value);
      continue;
    }

    try {
      data[normalizedKey] = JSON.stringify(value);
    } catch (_) {
      data[normalizedKey] = String(value);
    }
  }

  return data;
}

function parseFcmError(rawText: string): { message: string; unregistered: boolean } {
  try {
    const parsed = JSON.parse(rawText) as {
      error?: {
        message?: string;
        status?: string;
        details?: Array<Record<string, unknown>>;
      };
    };

    const message = (parsed.error?.message ?? rawText).toString();
    const status = (parsed.error?.status ?? "").toString().toUpperCase();
    const details = Array.isArray(parsed.error?.details) ? parsed.error?.details : [];
    const codeFromDetails = details
      .map((d) => (d.errorCode ?? "").toString().toUpperCase())
      .find((x) => x.length > 0) ?? "";

    const lowerMessage = message.toLowerCase();
    const unregistered = codeFromDetails === "UNREGISTERED" ||
      codeFromDetails === "REGISTRATION_TOKEN_NOT_REGISTERED" ||
      status === "UNREGISTERED" ||
      lowerMessage.includes("registration token is not a valid fcm registration token") ||
      lowerMessage.includes("requested entity was not found");

    return { message, unregistered };
  } catch (_) {
    return { message: rawText, unregistered: false };
  }
}

async function sendPushWithFcm(job: QueueJob, tokens: string[]) {
  if (tokens.length === 0) {
    throw new Error("No active push tokens");
  }

  const { accessToken, projectId } = await getFcmAccessToken();
  const endpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const data = buildFcmData(job);

  let sent = 0;
  const failures: string[] = [];

  for (const rawToken of tokens) {
    const token = rawToken.trim();
    if (!token) continue;

    if (token.startsWith("ExponentPushToken[")) {
      await deactivatePushToken(token);
      failures.push("Legacy Expo token was deactivated");
      continue;
    }

    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: job.title,
            body: job.body,
          },
          data,
          android: { priority: "high" },
          apns: {
            headers: {
              "apns-priority": "10",
            },
          },
        },
      }),
    });

    if (response.ok) {
      sent += 1;
      continue;
    }

    const text = await response.text();
    const parsed = parseFcmError(text);
    if (parsed.unregistered) {
      await deactivatePushToken(token);
    }
    failures.push(parsed.message);
  }

  if (sent === 0) {
    const reason = failures[0] ?? "Unknown push delivery error";
    throw new Error(`FCM delivery failed: ${reason}`);
  }

  if (failures.length > 0) {
    console.warn(`FCM partial delivery for job ${job.id}:`, failures.join(" | "));
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
        if (!dryRun) await sendPushWithFcm(job, tokens);
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
