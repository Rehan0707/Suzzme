const previews = {
  today: '<div class="demo-label">WHAT MATTERS TODAY <span>↗</span></div><h4>A little breathing room.</h4><p>Your first meeting is at 10. Review your notes, make a coffee, and ease into the day.</p><div class="demo-meta"><span class="mini-icon">▦</span> Design catch-up <span>10:00 AM</span></div>',
  ask: '<div class="demo-label">ASK SUZZME <span>◌</span></div><h4>“What do I need to do today?”</h4><p>You have a design catch-up this morning and a reminder to pick up the parcel at 3.</p><div class="demo-meta"><span class="mini-icon">✓</span> Grounded in Calendar & Reminders</div>',
  memory: '<div class="demo-label">PERSONAL MEMORY <span>◌</span></div><h4>The little things that make you, you.</h4><p>“I prefer to keep my mornings free for focused work.”</p><div class="demo-meta"><span class="mini-icon">◌</span> A preference you can review or delete</div>',
  action: '<div class="demo-label">REVIEW BEFORE ACTION <span>✓</span></div><h4>Create a reminder?</h4><p>Pick up the parcel · Today at 3:00 PM</p><div class="demo-meta"><span class="mini-icon">✓</span> Nothing changes until you confirm</div>'
};
const content = document.querySelector('#demo-content');
content.innerHTML = previews.today;
const phonePreviews = {
  today: '<small>YOUR DAILY SUMMARY</small><strong>Room for what matters.</strong><p>Your first meeting is at 10. There’s time to take it slow.</p><span>Open Daily Summary ↗</span>',
  ask: '<small>ASK SUZZME</small><strong>What’s ahead today?</strong><p>Your design catch-up is at 10. Pick up the parcel this afternoon.</p><span>Based on Calendar & Reminders</span>',
  memory: '<small>PERSONAL MEMORY</small><strong>The details you keep.</strong><p>You prefer quiet mornings for focused work. You can review or remove this anytime.</p><span>Memory stays in your control</span>',
  action: '<small>REVIEW FIRST</small><strong>Create a reminder?</strong><p>Pick up the parcel · Today at 3:00 PM</p><span>Nothing changes until you confirm</span>'
};
const phoneCard = document.querySelector('.phone-card');
const previewStories = {
  today: ['01 / YOUR DAY', 'Know what needs you.', 'Calendar and reminders become a calmer Daily Summary, with source limits made clear.'],
  ask: ['02 / CONVERSATION', 'Ask in your own words.', 'Use voice or text to ask about your permitted context and follow up naturally.'],
  memory: ['03 / MEMORY', 'Keep the context that lasts.', 'Useful preferences, people, and projects stay available for you to inspect, correct, or delete.'],
  action: ['04 / ACTION', 'Your approval comes first.', 'Suzzme proposes supported calendar and reminder changes for your review, then verifies what happened.']
};
const previewStory = document.querySelector('.preview-story');
document.querySelectorAll('[data-mode]').forEach(button => {
  button.addEventListener('click', () => {
    document.querySelectorAll('[data-mode]').forEach(tab => {
      const isActive = tab.dataset.mode === button.dataset.mode;
      tab.classList.toggle('active', isActive);
      tab.setAttribute('aria-pressed', String(isActive));
    });
    content.innerHTML = previews[button.dataset.mode];
    phoneCard.innerHTML = phonePreviews[button.dataset.mode];
    const [index, title, description] = previewStories[button.dataset.mode];
    previewStory.querySelector('.preview-story-index').textContent = index;
    previewStory.querySelector('h2').textContent = title;
    previewStory.querySelector('p').textContent = description;
    content.classList.remove('is-changing');
    phoneCard.classList.remove('is-changing');
    void content.offsetWidth;
    content.classList.add('is-changing');
    phoneCard.classList.add('is-changing');
    previewStory.classList.remove('is-changing');
    void previewStory.offsetWidth;
    previewStory.classList.add('is-changing');
  });
});
document.querySelector('#year').textContent = new Date().getFullYear();

const progress = document.querySelector('.scroll-progress');
let progressPending = false;
function updateProgress() {
  const available = document.documentElement.scrollHeight - window.innerHeight;
  progress.style.setProperty('--scroll-progress', `${available > 0 ? window.scrollY / available * 100 : 0}%`);
  document.body.classList.toggle('has-scrolled', window.scrollY > 40);
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const hero = document.querySelector('.hero');
    if (window.scrollY < hero.offsetHeight) hero.style.setProperty('--landscape-shift', `${Math.min(window.scrollY * 0.08, 55)}px`);
  }
  progressPending = false;
}
window.addEventListener('scroll', () => {
  if (!progressPending) {
    progressPending = true;
    requestAnimationFrame(updateProgress);
  }
}, { passive: true });
window.addEventListener('resize', updateProgress);
updateProgress();

const waitlistDialog = document.querySelector('#waitlist-dialog');
const waitlistForm = document.querySelector('#waitlist-form');
const waitlistError = document.querySelector('#waitlist-error');
const waitlistSuccess = document.querySelector('#waitlist-success');
const waitlistSubmit = waitlistForm.querySelector('.waitlist-submit');
document.querySelectorAll('.waitlist-trigger').forEach(trigger => {
  trigger.addEventListener('click', () => {
    waitlistDialog.showModal();
    if (!waitlistForm.hidden) document.querySelector('#waitlist-email').focus();
  });
});
document.querySelector('.waitlist-close').addEventListener('click', () => waitlistDialog.close());
document.querySelector('.waitlist-done').addEventListener('click', () => waitlistDialog.close());
waitlistDialog.addEventListener('click', event => {
  if (event.target === waitlistDialog) waitlistDialog.close();
});
waitlistForm.addEventListener('submit', async event => {
  event.preventDefault();
  if (!waitlistForm.reportValidity()) return;
  waitlistError.hidden = true;
  waitlistSubmit.disabled = true;
  waitlistSubmit.firstChild.textContent = 'Joining… ';
  try {
    const fields = new FormData(waitlistForm);
    const response = await fetch('/api/waitlist', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: fields.get('email'),
        platform: fields.get('platform'),
        website: fields.get('website')
      })
    });
    if (!response.ok) throw new Error('Could not save your signup.');
    waitlistForm.hidden = true;
    waitlistSuccess.hidden = false;
    waitlistSuccess.querySelector('.waitlist-done').focus();
  } catch {
    waitlistError.textContent = 'We couldn’t save your place. Please try again in a moment.';
    waitlistError.hidden = false;
  } finally {
    waitlistSubmit.disabled = false;
    waitlistSubmit.firstChild.textContent = 'Join the waitlist ';
  }
});

// Reveal the story as it enters view; reduced motion keeps every section immediate.
if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches && 'IntersectionObserver' in window) {
  const revealObserver = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.remove('is-pending');
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.08 });
  document.querySelectorAll('.experience-heading, .section-heading, .feature-card, .presence, .privacy-heading, .privacy-points, .faq, .closing').forEach(element => {
    element.classList.add('reveal', 'is-pending');
    revealObserver.observe(element);
  });
}

// Arrow keys move through each feature group without adding extra tab stops.
document.querySelectorAll('[role="group"]').forEach(group => {
  group.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key) || !event.target.matches('[data-mode]')) return;
    const buttons = [...group.querySelectorAll('[data-mode]')];
    let index = buttons.indexOf(event.target);
    if (event.key === 'Home') index = 0;
    else if (event.key === 'End') index = buttons.length - 1;
    else index = (index + (event.key === 'ArrowRight' ? 1 : -1) + buttons.length) % buttons.length;
    event.preventDefault();
    buttons[index].focus();
    buttons[index].click();
  });
});

// A user-started, pausable walkthrough of the four illustrative product states.
const demoPlay = document.querySelector('#demo-play');
let demoTimer = null;
const walkthroughModes = ['today', 'ask', 'memory', 'action'];
function stopWalkthrough() {
  clearInterval(demoTimer);
  demoTimer = null;
  demoPlay.textContent = '▷ Play demo';
  demoPlay.setAttribute('aria-pressed', 'false');
}
demoPlay.addEventListener('click', () => {
  if (demoTimer) return stopWalkthrough();
  demoPlay.textContent = 'Ⅱ Pause demo';
  demoPlay.setAttribute('aria-pressed', 'true');
  demoTimer = setInterval(() => {
    if (document.querySelector('.browser-demo').classList.contains('showing-notch')) {
      const controls = [...document.querySelectorAll('[data-native-state]')];
      const index = controls.findIndex(control => control.getAttribute('aria-pressed') === 'true');
      controls[(index + 1) % controls.length].click();
      return;
    }
    const active = document.querySelector('.experience-switcher [aria-pressed="true"]');
    const next = (walkthroughModes.indexOf(active?.dataset.mode || 'today') + 1) % walkthroughModes.length;
    document.querySelector('.experience-switcher [data-mode="' + walkthroughModes[next] + '"]').click();
  }, 4500);
});
document.querySelectorAll('[data-mode]').forEach(button => button.addEventListener('click', event => {
  if (event.isTrusted) stopWalkthrough();
}));
document.addEventListener('visibilitychange', () => { if (document.hidden) stopWalkthrough(); });

const nativeTab = document.querySelector('.native-demo-tab');
const demoStage = document.querySelector('.browser-demo');
const nativeDescriptions = {
 listening: 'Listening… A compact surface below the physical notch.',
 reasoning: 'Thinking it through… The face stays visible while Suzzme processes.',
 awaitingConfirmation: 'Waiting for your confirmation. The real surface expands to show the proposed change and its controls.',
 speaking: 'Speaking… A response appears beneath the familiar face.',
 success: 'Ready. A brief completion state before Suzzme returns to calm.'
};
nativeTab.addEventListener('click', () => {
 stopWalkthrough();
 demoStage.classList.add('showing-notch');
 nativeTab.setAttribute('aria-pressed','true');
 document.querySelectorAll('.experience-switcher [data-mode]').forEach(button => {button.classList.remove('active');button.setAttribute('aria-pressed','false');});
});
document.querySelectorAll('[data-mode]').forEach(button => button.addEventListener('click', () => {
 demoStage.classList.remove('showing-notch');
 nativeTab.setAttribute('aria-pressed','false');
}));
document.querySelectorAll('[data-native-state]').forEach(button => button.addEventListener('click', event => {
 if (event.isTrusted) stopWalkthrough();
 document.querySelectorAll('[data-native-state]').forEach(control => control.setAttribute('aria-pressed',String(control === button)));
 document.querySelectorAll('.native-presence-image').forEach(image => {
 image.src = 'native-presence/Dark-' + button.dataset.nativeState + '.png';
 image.alt = 'Actual Suzzme SwiftUI Mac presence: ' + button.textContent;
 });
 document.querySelector('.native-state-description').textContent = nativeDescriptions[button.dataset.nativeState];
}));
nativeTab.click();

const detailToggle = document.querySelector('.notch-detail-toggle');
detailToggle.addEventListener('click', () => {
 const closeUp = demoStage.classList.toggle('notch-closeup');
 detailToggle.setAttribute('aria-pressed',String(closeUp));
 detailToggle.textContent = closeUp ? '↙ Show full MacBook' : '⌕ View notch close-up';
});
document.querySelector('.native-state-controls').addEventListener('keydown', event => {
 if (!['ArrowLeft','ArrowRight'].includes(event.key)) return;
 const controls = [...document.querySelectorAll('[data-native-state]')];
 const index = controls.indexOf(event.target);
 if (index < 0) return;
 event.preventDefault();
 const next = controls[(index + (event.key === 'ArrowRight' ? 1 : -1) + controls.length) % controls.length];
 next.focus(); next.click(); stopWalkthrough();
});
