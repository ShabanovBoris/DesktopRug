'use strict';

const patterns = {
  heriz: 'Heriz · Garnet',
  indigo: 'Isfahan · Indigo',
  'soviet-red': 'Soviet · Red',
  'soviet-floral': 'Soviet · Floral',
};
const image = document.getElementById('pattern-image');
const name = document.getElementById('pattern-name');
const patternButtons = document.querySelectorAll('[data-pattern]');

for (const button of patternButtons) {
  button.addEventListener('click', () => {
    const pattern = button.dataset.pattern;
    image.src = `assets/${pattern}.png`;
    image.alt = `${patterns[pattern]} rug texture included in Desktop Rug`;
    name.textContent = patterns[pattern];
    for (const choice of patternButtons) choice.setAttribute('aria-pressed', String(choice === button));
  });
}

document.getElementById('share-button').addEventListener('click', async () => {
  const url = 'https://github.com/ShabanovBoris/DesktopRug';
  const status = document.getElementById('share-status');
  try {
    if (navigator.share) {
      await navigator.share({ title: 'Desktop Rug', text: 'Desktop cleanup, the real-life way: sweep the mess under a rug.', url });
      status.textContent = 'Thanks for sharing this very familiar cleanup trick.';
    } else if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(url);
      status.textContent = 'GitHub link copied. Send it to someone who cleans like this.';
    } else {
      status.textContent = `Share this link: ${url}`;
    }
  } catch (error) {
    if (error.name !== 'AbortError') status.textContent = `Share this link: ${url}`;
  }
});
