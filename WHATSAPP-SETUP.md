# Configurar notificações automáticas do Crédito Ágil pelo WhatsApp

A integração foi preparada para enviar uma mensagem quando um administrador muda o status para **Pendente**, **Aprovado** ou **Recusado**. Só envia para clientes que marcaram a autorização opcional no formulário. O status continua salvo mesmo se a API de mensagens falhar.

## 1. Aplicar a migração do banco

1. Abra o projeto Supabase `vofdcnjnedxnqbnpeoon`.
2. Entre em **SQL Editor** e crie uma consulta.
3. Copie e execute todo o arquivo `supabase-whatsapp-notifications-migration.sql`.
4. Confirme que a execução terminou sem erro.

A migração substitui a função de envio de solicitação para salvar o consentimento do WhatsApp. Não a execute antes de conferir que o arquivo foi copiado por inteiro.

## 2. Configurar o WhatsApp Business da Meta

Na [Central de Desenvolvedores do WhatsApp](https://whatsappbusiness.com/pt-br/developers/developer-hub/), configure a WhatsApp Business Platform / Cloud API e obtenha:
- um token de acesso da API;
- o **Phone Number ID** do número remetente;
- uma versão da Graph API que esteja atualmente suportada pela Meta.

Crie e envie para aprovação um modelo de mensagem em português (Brasil), com nome `credito_agil_status_update`, categoria adequada às regras da Meta, e exatamente três variáveis no corpo, nesta ordem:

```text
Olá {{1}}, sua solicitação no Crédito Ágil teve o status atualizado para {{2}}. Valor solicitado: {{3}}. Esta mensagem informa apenas o status cadastrado; não confirma liberação de crédito nem depósito.
```

As mensagens iniciadas pela empresa dependem de um modelo aprovado e das regras/consentimento do WhatsApp. Não use a integração para prometer aprovação ou depósito.

## 3. Guardar credenciais como secrets no Supabase

Em **Supabase → Edge Functions → Secrets** (ou na área de secrets do projeto), adicione estes secrets:
- `WHATSAPP_ACCESS_TOKEN` — token da Cloud API;
- `WHATSAPP_PHONE_NUMBER_ID` — Phone Number ID do remetente;
- `WHATSAPP_GRAPH_API_VERSION` — versão atualmente suportada, por exemplo no formato `vNN.0`;
- `WHATSAPP_STATUS_TEMPLATE_NAME` — `credito_agil_status_update` (opcional se usar o nome padrão).

O Supabase já fornece à Edge Function as variáveis internas `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY`. **Nunca coloque token da Meta nem service-role key no HTML, no GitHub ou em mensagens.**

## 4. Implantar a Edge Function

A pasta `supabase/functions/notify-whatsapp-status/index.ts` contém o código. Em um computador com o Supabase CLI instalado, na pasta local deste repositório execute:

```bash
supabase login
supabase link --project-ref vofdcnjnedxnqbnpeoon
supabase functions deploy notify-whatsapp-status
```

A função exige sessão autenticada e verifica que o usuário está em `admin_users` antes de enviar. O painel chama a função somente depois de salvar uma mudança de status.

## 5. Testar sem enviar mensagens a clientes

1. Use um número de teste autorizado pela Meta e um destinatário de teste.
2. Envie uma solicitação marcando a autorização de WhatsApp.
3. Entre no painel administrativo e mude o status dessa solicitação.
4. Verifique a resposta do painel e os logs da Edge Function. A API aceitar a mensagem não garante que ela foi entregue.

Se a migração e a função ainda não tiverem sido executadas/configuradas, o painel poderá salvar o status, mas a notificação automática não será enviada. Clientes que não marcaram a autorização não recebem mensagem.
