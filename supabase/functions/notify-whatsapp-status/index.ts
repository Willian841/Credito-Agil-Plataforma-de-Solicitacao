import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://willian841.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Método não permitido." });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json(401, { error: "Autenticação necessária." });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const metaToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
  const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  const graphVersion = Deno.env.get("WHATSAPP_GRAPH_API_VERSION");
  const templateName = Deno.env.get("WHATSAPP_STATUS_TEMPLATE_NAME") || "credito_agil_status_update";

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !metaToken || !phoneNumberId || !graphVersion) {
    return json(503, { error: "Integração WhatsApp ainda não configurada no servidor." });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const accessToken = authHeader.slice("Bearer ".length);\n  const { data: userData, error: userError } = await userClient.auth.getUser(accessToken);
  if (userError || !userData.user) return json(401, { error: "Sessão inválida." });

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: admin, error: adminError } = await adminClient
    .from("admin_users").select("user_id").eq("user_id", userData.user.id).maybeSingle();
  if (adminError || !admin) return json(403, { error: "Somente administradores autorizados podem enviar notificações." });

  let body: { application_id?: string; status?: string };
  try { body = await req.json(); } catch { return json(400, { error: "Corpo JSON inválido." }); }
  const applicationId = body.application_id;
  const requestedStatus = body.status;
  if (!applicationId || !["Pendente", "Aprovado", "Recusado"].includes(requestedStatus || "")) {
    return json(400, { error: "Solicitação ou status inválido." });
  }

  const { data: application, error: applicationError } = await adminClient
    .from("loan_applications")
    .select("id,full_name,phone,loan_amount,status,whatsapp_opt_in")
    .eq("id", applicationId).maybeSingle();
  if (applicationError || !application) return json(404, { error: "Solicitação não encontrada." });
  if (application.status !== requestedStatus) return json(409, { error: "O status no banco não corresponde ao status solicitado." });
  if (!application.whatsapp_opt_in) return json(200, { sent: false, skipped: true, reason: "O cliente não autorizou notificações por WhatsApp." });

  const digits = String(application.phone || "").replace(/\D/g, "");
  const recipient = digits.startsWith("55") ? digits : "55" + digits;
  if (recipient.length < 12 || recipient.length > 13) return json(422, { error: "Telefone do cliente inválido para WhatsApp." });

  const amount = Number(application.loan_amount).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const messagePayload = {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: recipient,
    type: "template",
    template: {
      name: templateName,
      language: { code: "pt_BR" },
      components: [{
        type: "body",
        parameters: [
          { type: "text", text: String(application.full_name || "cliente").slice(0, 120) },
          { type: "text", text: requestedStatus },
          { type: "text", text: amount },
        ],
      }],
    },
  };

  const metaResponse = await fetch("https://graph.facebook.com/" + graphVersion + "/" + phoneNumberId + "/messages", {
    method: "POST",
    headers: { Authorization: "Bearer " + metaToken, "Content-Type": "application/json" },
    body: JSON.stringify(messagePayload),
  });
  const metaResult = await metaResponse.json().catch(() => ({}));
  if (!metaResponse.ok) {
    console.error("WhatsApp Cloud API error", metaResponse.status, JSON.stringify(metaResult).slice(0, 1000));
    return json(502, { error: "A Meta não aceitou a mensagem. Verifique o modelo aprovado e as credenciais do WhatsApp Business." });
  }
  return json(200, { sent: true, message_id: metaResult?.messages?.[0]?.id || null, status: requestedStatus });
});
