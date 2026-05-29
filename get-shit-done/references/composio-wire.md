# Composio wiring recipe

How to add a toolkit + connection via the Composio v3 API. API key: Infisical `/personal/COMPOSIO_API_KEY`. MCP server `arnis-claude-code-multi` = `0fb0df7b-9260-4c77-817b-728d81535636`.

```bash
CK=$(infisical secrets get COMPOSIO_API_KEY --path=/personal --projectId=5c0c4346-3c12-4ccd-9c36-a2262eab9987 --env=dev --domain=https://secrets.elevateoco.com --plain --silent)
H=(-H "X-API-Key: $CK" -H "Content-Type: application/json")
B=https://backend.composio.dev/api/v3
```

## 1. Discover auth mode
```bash
/usr/bin/curl -s "${H[@]}" "$B/toolkits/<slug>" | python3 -c "import json,sys;d=json.load(sys.stdin);print([(a['mode'],[f['name'] for f in a['fields']['connected_account_initiation']['required']]) for a in d.get('auth_config_details',[])], d.get('composio_managed_auth_schemes'))"
```

## 2a. API_KEY toolkit (have key in Infisical)
```bash
# create auth_config (custom auth)
AC=$(/usr/bin/curl -s "${H[@]}" -X POST "$B/auth_configs" -d '{"toolkit":{"slug":"<slug>"},"auth_config":{"type":"use_custom_auth","authScheme":"API_KEY","name":"<slug>-arnis","credentials":{}}}' | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('id') or d.get('auth_config',{}).get('id'))")
# create connection (field name from step 1, usually generic_api_key)
/usr/bin/curl -s "${H[@]}" -X POST "$B/connected_accounts" -d "{\"auth_config\":{\"id\":\"$AC\"},\"connection\":{\"user_id\":\"arnis\",\"state\":{\"authScheme\":\"API_KEY\",\"val\":{\"generic_api_key\":\"<KEY>\"}}}}"
```
Cloudflare needs `generic_api_key`+`generic_id` (email). Shopify needs `subdomain`+`generic_api_key`.

## 2b. Composio-managed OAuth toolkit → link flow
```bash
AC=$(/usr/bin/curl -s "${H[@]}" -X POST "$B/auth_configs" -d '{"toolkit":{"slug":"<slug>"},"auth_config":{"type":"use_composio_managed_auth","name":"<slug>-arnis"}}' | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('id') or d.get('auth_config',{}).get('id'))")
# OAuth uses /link (NOT /connected_accounts) for managed auth:
/usr/bin/curl -s "${H[@]}" -X POST "$B/connected_accounts/link" -d "{\"auth_config_id\":\"$AC\",\"user_id\":\"arnis\"}" | python3 -c "import json,sys;print(json.load(sys.stdin).get('redirect_url'))"
```
OAuth redirect URLs expire fast — generate right before the user clicks; batch them.

## 2c. Custom OAuth (own Google client, for gmail/calendar/sheets/docs)
Reuse Composio Admin OAuth client (Infisical `/oauth/google/COMPOSIO_ADMIN_CLIENT_ID` + `_SECRET`); `type:use_custom_auth, authScheme:OAUTH2, credentials:{client_id,client_secret,scopes:[...]}`. Then `POST /connected_accounts {auth_config:{id},connection:{user_id}}` returns redirect_url.

## 3. Add toolkit to the MCP server
```bash
/usr/bin/curl -s "${H[@]}" -X PATCH "$B/mcp/0fb0df7b-9260-4c77-817b-728d81535636" -d '{"toolkits":["...full list incl new slug..."]}'
```
PATCH replaces the toolkit list — always send the COMPLETE list. Leaving `allowed_tools:[]` exposes all tools for those toolkits (don't pass a giant allowed_tools or tools/list overflows). Claude Code restart required to load new tools.

## Gotchas learned
- `infisical secrets delete` defaults to `--type=personal`; our secrets are shared → pass `--type=shared`.
- Twilio has NO Composio toolkit. Gemini needs no auth. GitHub/Discord/Stripe default to OAuth (Stripe also supports API_KEY — recreate as custom if you want key mode).
- MCP HTTP endpoint: `.../v3/mcp/<id>/mcp?user_id=arnis` with `X-API-Key` header.
