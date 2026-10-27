import { cfg } from '../config';

// fire-and-forget: a Telegram failure must never break a deposit/withdrawal
export function tg(text: string) {
  if (!cfg.tgToken || !cfg.tgChat) return;
  fetch(`https://api.telegram.org/bot${cfg.tgToken}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: cfg.tgChat, text, disable_web_page_preview: true }),
  })
    .then(async r => { if (!r.ok) console.error('Telegram error', r.status, await r.text()); })
    .catch(e => console.error('Telegram failed:', e.message));
}