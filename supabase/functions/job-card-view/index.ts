// job-card-view — karigar-facing magic-link page (R4d).
//
// The share_token IS the capability: anyone with the link can view this job
// card and post progress — the same trust model as forwarding the PDF on
// WhatsApp. Deployed with verify_jwt=false for that reason. The owner
// revokes a link by regenerating the token from JobCardPreviewView.
//
// GET  /job-card-view/<token>        → mobile-first HTML (Hinglish, big type)
// POST /job-card-view/<token>/event  → multipart {event, photo?} → insert
//                                      job_card_events row, 303 back (PRG)
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const EVENTS = ["started", "stitching_done", "ready"] as const;
const LABELS: Record<string, string> = {
  started: "Shuru kiya",
  stitching_done: "Silai poori",
  ready: "Taiyaar hai",
};
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const RATE_LIMIT_PER_DAY = 30;

Deno.serve(async (req) => {
  const url = new URL(req.url);
  // pathname: /job-card-view/<token>[/event]
  const parts = url.pathname.split("/").filter(Boolean);
  const token = parts[1];
  const isEvent = parts[2] === "event";
  if (!token) return text("Not found", 404);

  const { data: card } = await supabase.from("job_cards")
    .select("*").eq("share_token", token).maybeSingle();
  if (!card) return text("Link galat hai ya band ho gaya hai.", 404);

  if (req.method === "POST" && isEvent) return handleEvent(req, card, url);
  if (req.method === "GET" && !isEvent) return renderPage(card);
  return text("Method not allowed", 405);
});

function text(body: string, status: number): Response {
  return new Response(body, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}

async function handleEvent(req: Request, card: any, url: URL): Promise<Response> {
  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return text("Form data chahiye.", 400);
  }
  const event = String(form.get("event") ?? "");
  if (!(EVENTS as readonly string[]).includes(event)) {
    return text("Galat event.", 400);
  }

  // Rate limit: trailing-24h count per job card.
  const since = new Date(Date.now() - 86_400_000).toISOString();
  const { count } = await supabase.from("job_card_events")
    .select("id", { count: "exact", head: true })
    .eq("job_card_id", card.id)
    .gt("created_at", since);
  if ((count ?? 0) >= RATE_LIMIT_PER_DAY) {
    return text("Aaj ke liye limit ho gayi — kal try karo.", 429);
  }

  let wip_photo_path: string | null = null;
  const photo = form.get("photo");
  if (photo instanceof File && photo.size > 0) {
    if (photo.size > MAX_PHOTO_BYTES) {
      return text("Photo 5 MB se badi hai — chhoti photo bhejo.", 413);
    }
    if (photo.type !== "image/jpeg" && photo.type !== "image/png") {
      return text("Sirf JPEG ya PNG photo chalegi.", 415);
    }
    const ext = photo.type === "image/png" ? "png" : "jpg";
    const path = `${card.id}/${crypto.randomUUID()}.${ext}`;
    const { error: upErr } = await supabase.storage.from("karigar-wip")
      .upload(path, photo, { contentType: photo.type });
    if (!upErr) wip_photo_path = path;
  }

  await supabase.from("job_card_events").insert({
    boutique_id: card.boutique_id,
    job_card_id: card.id,
    event,
    wip_photo_path,
  });

  // PRG: refresh never reposts. (Events are append-only; a double-tap is
  // harmless anyway — latest event wins for display.)
  const backTo = url.pathname.replace(/\/event$/, "");
  return new Response(null, { status: 303, headers: { Location: backTo } });
}

async function renderPage(card: any): Promise<Response> {
  const { data: events } = await supabase.from("job_card_events")
    .select("*").eq("job_card_id", card.id)
    .order("created_at", { ascending: false }).limit(10);

  // First name only — never phone/address on this page.
  let firstName = "";
  if (card.customer_id) {
    const { data: cust } = await supabase.from("customers")
      .select("name").eq("id", card.customer_id).maybeSingle();
    firstName = (cust?.name ?? "").split(" ")[0];
  }

  const signed = async (bucket: string, path: string | null) => {
    if (!path) return null;
    const { data } = await supabase.storage.from(bucket).createSignedUrl(path, 3600);
    return data?.signedUrl ?? null;
  };
  const renderUrl = await signed("design-renders", card.render_image_path);
  const sketchUrl = await signed("design-sketches", card.sketch_image_path);
  const heroUrl = renderUrl ?? sketchUrl;

  const latest = events?.[0]?.event ?? null;

  const measurements = card.measurements_json
    ? Object.entries(card.measurements_json as Record<string, number>)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) =>
          `<tr><td>${esc(k.replaceAll("_", " "))}</td><td><b>${esc(String(v))}</b></td></tr>`)
        .join("")
    : "";

  const fabrics = Array.isArray(card.fabric_list_json)
    ? card.fabric_list_json.map((f: any) =>
        `<li>${esc(f.name ?? "")}${f.color ? ` (${esc(f.color)})` : ""} — ${esc(String(f.quantityMeters ?? f.quantity_meters ?? "?"))} m</li>`).join("")
    : "";

  const eventRows = (events ?? []).map((e: any) =>
    `<li>${LABELS[e.event] ?? esc(String(e.event))} · ${new Date(e.created_at).toLocaleString("en-IN", { timeZone: "Asia/Kolkata", day: "numeric", month: "short", hour: "numeric", minute: "2-digit" })}</li>`).join("");

  const buttons = EVENTS.map((ev) => `
    <form method="post" action="${esc(cardPath(card))}/event" enctype="multipart/form-data" style="margin:0 0 12px">
      <input type="hidden" name="event" value="${ev}">
      <label style="display:block;font-size:14px;color:#666;margin-bottom:4px">Photo (optional):
        <input type="file" name="photo" accept="image/jpeg,image/png"></label>
      <button type="submit" style="width:100%;min-height:56px;font-size:20px;border-radius:12px;border:2px solid ${latest === ev ? "#1a7f37" : "#ccc"};background:${latest === ev ? "#e6f4ea" : "#fff"};font-weight:600">
        ${LABELS[ev]}${latest === ev ? " ✓" : ""}
      </button>
    </form>`).join("");

  const html = `<!doctype html>
<html lang="hi-Latn"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Job ${esc(card.job_number ?? "")}</title>
</head>
<body style="font-family:-apple-system,Roboto,'Noto Sans',sans-serif;font-size:18px;line-height:1.5;margin:0;padding:16px;max-width:480px;margin-inline:auto;color:#1c1c1e">
  <h1 style="font-size:24px;margin:0 0 4px">Job ${esc(card.job_number ?? "")}</h1>
  <p style="margin:0 0 12px;color:#555">${esc(card.garment_type ?? "")}${card.occasion ? ` · ${esc(card.occasion)}` : ""}${firstName ? ` · ${esc(firstName)} ji ke liye` : ""}</p>
  ${card.due_date ? `<p style="font-size:22px;font-weight:700;background:#fff3cd;padding:10px 14px;border-radius:10px">Due date: ${esc(card.due_date)}</p>` : ""}
  ${heroUrl ? `<img src="${esc(heroUrl)}" alt="Design" style="width:100%;border-radius:12px;margin:12px 0">` : ""}
  ${fabrics ? `<h2 style="font-size:19px;margin:16px 0 6px">Kapda</h2><ul style="margin:0;padding-left:20px">${fabrics}</ul>` : ""}
  ${measurements ? `<h2 style="font-size:19px;margin:16px 0 6px">Naap (inches)</h2><table style="width:100%;border-collapse:collapse">${measurements}</table>` : ""}
  ${card.hindi_brief ? `<h2 style="font-size:19px;margin:16px 0 6px">Brief</h2><div style="border:1px solid #ddd;border-radius:10px;padding:12px;white-space:pre-wrap">${esc(card.hindi_brief)}</div>` : ""}
  <h2 style="font-size:19px;margin:20px 0 8px">Kaam ka status batao</h2>
  ${buttons}
  ${eventRows ? `<h2 style="font-size:19px;margin:16px 0 6px">Pichhle updates</h2><ul style="margin:0;padding-left:20px;color:#555">${eventRows}</ul>` : ""}
</body></html>`;

  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

function cardPath(card: any): string {
  return `/functions/v1/job-card-view/${card.share_token}`;
}

function esc(s: string): string {
  return String(s).replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}
