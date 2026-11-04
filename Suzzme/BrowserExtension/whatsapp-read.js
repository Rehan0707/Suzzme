// Runs only after an explicit popup action, in the isolated extension world.
export function readOpenWhatsAppChat() {
  if (location.origin !== 'https://web.whatsapp.com' || document.visibilityState !== 'visible') return null;
  const main = document.querySelector('#main');
  const name = main?.querySelector('header [title]')?.getAttribute('title');
  if (!name) return null;
  const rows = [...main.querySelectorAll('[data-pre-plain-text]')].slice(-20);
  const text = rows.map(row => (row.getAttribute('data-pre-plain-text') ?? '') +
    [...row.querySelectorAll('.selectable-text')].map(node => node.textContent).join(' ')).join('\n').slice(0,3000);
  return text.trim() ? {name, text} : null;
}
