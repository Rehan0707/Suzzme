const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const preference = matchMedia('(prefers-reduced-motion: reduce)');
let reduced = preference.matches;
let dayTimer, presenceTimer, cueTimer, heroTimer;
let dayIndex = 0, presenceIndex = 0;
const dayViews = [
  `<p class="content-intro">A few pieces of your day. One clear picture.</p><div class="context-row"><img class="source-icon" src="assets/apps/calendar.png" alt=""><div><b>Design catch-up</b><small>10:30–11:30 AM · Calendar</small></div><span>Connected</span></div><div class="context-row"><img class="source-icon" src="assets/apps/mail.png" alt=""><div><b>Sarah is waiting for your sign-off</b><small>Project update · Mail</small></div><span>Connected</span></div><div class="context-row"><img class="source-icon" src="assets/apps/reminders.png" alt=""><div><b>Review the launch designs</b><small>Due today · Reminders</small></div><span>Connected</span></div>`,
  `<p class="content-intro">Here’s the shape of your morning.</p><div class="summary-message">Your first meeting is at <b>10:30 AM</b>. Review the launch designs beforehand, then send <b>Sarah’s sign-off</b> this afternoon.<br>You have a quiet window to focus first.</div><div class="summary-tags"><span>1 meeting</span><span>2 priorities</span><span>A little breathing room</span></div>`,
  `<p class="content-intro">A suggested plan, built around your commitments.</p><div class="plan-row"><time>9:00</time><span class="plan-line"></span><div><b>A little time to focus</b><small>Review launch designs · Until 10:15</small></div></div><div class="plan-row"><time>10:30</time><span class="plan-line"></span><div><b>Design catch-up</b><small>Already on your calendar · Until 11:30</small></div></div><div class="plan-row"><time>14:00</time><span class="plan-line"></span><div><b>Close the loop with Sarah</b><small>Review and send the project sign-off</small></div></div>`
];
function animateContent(element) {
  if (!reduced) element.animate([{opacity:0,transform:'translateY(7px)'},{opacity:1,transform:'translateY(0)'}],{duration:280,easing:'cubic-bezier(.23,1,.32,1)'});
}
// Force Safari and modern browsers to immediately invalidate old cached tab favicon
(function forceFaviconRefresh() {
  const head = document.head || document.getElementsByTagName('head')[0];
  const ts = Date.now();
  ['icon', 'shortcut icon', 'apple-touch-icon', 'apple-touch-icon-precomposed'].forEach(rel => {
    document.querySelectorAll(`link[rel="${rel}"]`).forEach(el => el.remove());
    const link = document.createElement('link');
    link.type = 'image/png';
    link.rel = rel;
    link.href = `assets/suzzme-app-icon.png?t=${ts}`;
    head.appendChild(link);
  });
})();
const dayScreens = ['home', 'sources', 'apps'];
function renderDay(index, announce = false) {
  if (index < 0 || index >= dayViews.length) return;
  dayIndex = index;
  $$('.steps .step').forEach(button => {
    const active = Number(button.dataset.step) === dayIndex;
    button.setAttribute('aria-pressed', active);
    button.classList.toggle('active', active);
  });
  $$('.mac-sidebar button[data-step]').forEach(button => {
    button.setAttribute('aria-pressed', Number(button.dataset.step) === dayIndex);
  });
  $$('.app-tabs button[data-step]').forEach(button => {
    button.setAttribute('aria-pressed', Number(button.dataset.step) === dayIndex);
  });
  if ($('#day-content') && dayViews[dayIndex]) {
    $('#day-content').innerHTML = dayViews[dayIndex];
    if (!reduced) animateContent($('#day-content'));
  }
  if (announce && $('#announcement')) {
    const messages = [
      'Step 1: Bring it all together with your calendar, reminders, and notes.',
      'Step 2: Find the important bits in your thoughtful Daily Summary.',
      'Step 3: Make room for your day with an intelligent schedule.'
    ];
    $('#announcement').textContent = messages[dayIndex] || '';
  }
}
function setMacView(viewKey, announce = false) {
  const stepIdx = dayScreens.indexOf(viewKey);
  if (stepIdx !== -1) renderDay(stepIdx, announce);
}
function stopDay() {
  clearTimeout(dayTimer);
  dayTimer = null;
  const playBtn = $('#play-day');
  if (playBtn) playBtn.textContent = '▶  Play the story';
}
$$('.steps [data-step]').forEach(button => button.addEventListener('click', () => {
  stopDay();
  renderDay(Number(button.dataset.step), true);
}));
$$('.mac-sidebar button[data-step], .app-tabs button[data-step]').forEach(btn => {
  btn.addEventListener('click', () => {
    stopDay();
    renderDay(Number(btn.dataset.step), true);
  });
});
$$('[data-mac-view]').forEach(button => button.addEventListener('click', () => {
  const actual = button.dataset.macView === 'actual';
  $$('[data-mac-view]').forEach(item => item.setAttribute('aria-pressed', item === button));
  if ($('.mac-actual')) $('.mac-actual').hidden = !actual;
  if ($('.mac-live')) $('.mac-live').hidden = actual;
  if (actual) stopDay();
}));
$('#play-day')?.addEventListener('click', () => {
  if (dayTimer) { stopDay(); return; }
  renderDay(0, true);
  $('#play-day').textContent = 'Ⅱ  Pause the story';
  function next(){
    if(dayIndex < 2){
      renderDay(dayIndex + 1, true);
      dayTimer = setTimeout(next, 3400);
    } else {
      stopDay();
    }
  }
  dayTimer = setTimeout(next, 3400);
});
const states = [
  {island:'Gathering your day',title:'Your day, coming together.',description:'Finding the important bits.',footer:'A little clarity is on its way',badge:'IN PROGRESS',progress:.3,symbol:'◌'},
  {island:'Connecting the dots',title:'A little space to think.',description:'Making sense of your context.',footer:'Looking at the bigger picture',badge:'THINKING',progress:.6,symbol:'⋯'},
  {island:'Your day, in a few words',title:'Let’s talk about your day.',description:'Your summary, read back to you.',footer:'A thoughtful start to your morning',badge:'SPEAKING',progress:.85,symbol:'≋'},
  {island:'Your summary is ready',title:'A good day starts here.',description:'Your summary and plan are ready.',footer:'Ready to continue in Suzzme',badge:'ALL READY',progress:1,symbol:'✓'}
];
function renderPresence(index, announce = false) {
  if (!$('#island-text')) return;
  presenceIndex=index; const state=states[index];
  $$('[data-state]').forEach(button=>button.setAttribute('aria-pressed',Number(button.dataset.state)===index));
  $('#island-text').textContent=state.island;
  $('#activity-title').textContent=state.title;
  $('#activity-description').textContent=state.description;
  $('#activity-footer').textContent=state.footer;
  $('#activity-badge').textContent=state.badge;
  $('#activity-symbol').textContent=state.symbol;
  $('#activity-progress').style.transform=`scaleX(${state.progress})`;
  $('#island').classList.toggle('compact',index===3);
  clearTimeout(cueTimer); $('.phone')?.classList.remove('cue');
  if(!reduced && index!==3){requestAnimationFrame(()=>{if(!document.hidden && !reduced)$('.phone')?.classList.add('cue');});cueTimer=setTimeout(()=>$('.phone')?.classList.remove('cue'),1400);}
  if($('#live-activity')) animateContent($('#live-activity'));
  if(announce && $('#announcement')) $('#announcement').textContent=state.title+' '+state.description;
}
function stopPresence(){clearTimeout(presenceTimer);presenceTimer=null;if($('#play-presence')) $('#play-presence').textContent='▶  Play companion sequence';}
$$('[data-state]').forEach(button=>button.addEventListener('click',()=>{stopPresence();renderPresence(Number(button.dataset.state),true);}));
$('#play-presence')?.addEventListener('click',()=>{
  if(presenceTimer){stopPresence();return;}
  renderPresence(0,true);if($('#play-presence')) $('#play-presence').textContent='Ⅱ  Pause companion sequence';
  function next(){if(presenceIndex<3){renderPresence(presenceIndex+1,true);presenceTimer=setTimeout(next,2600);}else stopPresence();}
  presenceTimer=setTimeout(next,2600);
});
function openHowModal(target = 'mac') {
  const modal = $('#how-it-works-modal');
  if (!modal) return;
  modal.classList.add('is-open');
  modal.setAttribute('aria-hidden', 'false');
  const modalBody = $('.how-modal-body');
  if (target === 'iphone') {
    setTimeout(() => {
      const iphoneView = $('#iphone-preview');
      if (iphoneView) {
        iphoneView.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    }, 70);
  } else if (modalBody) {
    modalBody.scrollTop = 0;
  }
  if ($('#announcement')) {
    $('#announcement').textContent = 'How it works preview opened. Press Escape to close.';
  }
}

function closeHowModal() {
  const modal = $('#how-it-works-modal');
  if (!modal) return;
  modal.classList.remove('is-open');
  modal.setAttribute('aria-hidden', 'true');
  stopDay();
  stopPresence();
  if ($('#announcement')) {
    $('#announcement').textContent = 'Preview closed.';
  }
}

$('#nav-how')?.addEventListener('click', () => openHowModal('mac'));
$('#nav-mac')?.addEventListener('click', () => openHowModal('mac'));
$('#nav-presence')?.addEventListener('click', () => openHowModal('iphone'));
$('#nav-demo')?.addEventListener('click', () => openHowModal('mac'));
$('#hero-demo-btn')?.addEventListener('click', () => openHowModal('mac'));
$('#foot-mac')?.addEventListener('click', () => openHowModal('mac'));
$('#foot-iphone')?.addEventListener('click', () => openHowModal('iphone'));
$('#foot-mac')?.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openHowModal('mac'); } });
$('#foot-iphone')?.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openHowModal('iphone'); } });

$('#close-how-modal')?.addEventListener('click', closeHowModal);
$('#how-it-works-modal')?.addEventListener('click', (e) => {
  if (e.target === $('#how-it-works-modal')) closeHowModal();
});
window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && $('#how-it-works-modal')?.classList.contains('is-open')) {
    closeHowModal();
  }
});

$('#hero-play')?.addEventListener('click', (e) => {
  e.preventDefault();
  clearTimeout(heroTimer);
  $('.hero-art')?.classList.remove('replaying');
  requestAnimationFrame(() => $('.hero-art')?.classList.add('replaying'));
  openHowModal('mac');
  heroTimer = setTimeout(() => { $('.hero-art')?.classList.remove('replaying'); }, reduced ? 0 : 1200);
});

function setMotion(value){reduced=value;document.documentElement.classList.toggle('reduce-motion',value);if($('#motion-toggle')){$('#motion-toggle').textContent=value?'Motion reduced':'Motion on';$('#motion-toggle').setAttribute('aria-pressed',value);}if($('#hero-motion')){$('#hero-motion').textContent=value?'Resume motion':'Pause motion';$('#hero-motion').setAttribute('aria-pressed',value);}document.getAnimations().forEach(animation=>{if(value && animation.effect?.target?.closest('#day-content, #live-activity'))animation.finish();});if(value){clearTimeout(cueTimer);$('.phone')?.classList.remove('cue');}}
$('#motion-toggle')?.addEventListener('click',()=>setMotion(!reduced));preference.addEventListener('change',event=>setMotion(event.matches));
document.addEventListener('visibilitychange',()=>{if(document.hidden){stopDay();stopPresence();clearTimeout(cueTimer);clearTimeout(heroTimer);$('.phone')?.classList.remove('cue');$('.hero-art')?.classList.remove('replaying');}});
const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');observer.unobserve(entry.target);}}),{threshold:.12});
$$('.section-heading,.day-demo,.presence-copy,.phone-stage,.device-card').forEach(element=>{element.classList.add('reveal');observer.observe(element);});
setMotion(reduced);renderDay(0);renderPresence(0);
const sceneObserver = new IntersectionObserver(entries => {
  $('.hero-art')?.classList.toggle('scene-paused', !entries[0].isIntersecting || document.hidden);
}, { threshold: .1 });
if ($('.hero-art')) sceneObserver.observe($('.hero-art'));
document.addEventListener('visibilitychange', () => {
  if (!$('.hero-art')) return;
  const rect = $('.hero-art').getBoundingClientRect();
  $('.hero-art').classList.toggle('scene-paused', document.hidden || rect.bottom <= 0 || rect.top >= innerHeight);
});

// Supplied Suzzme variants; original assets remain available in the repository.
$$('[data-mascot]').forEach(button => button.addEventListener('click', () => {
  const variant = button.dataset.mascot;
  $$('[data-mascot]').forEach(item => item.setAttribute('aria-pressed', item === button));
  $$('img[src^="assets/mascots/"]').forEach(img => img.src = `assets/mascots/${variant}.png`);
  $('.mascot-art')?.setAttribute('href', `assets/mascots/${variant}.png`);
  if ($('#announcement')) $('#announcement').textContent = `${variant[0].toUpperCase()+variant.slice(1)} Suzzme selected.`;
}));
$('#hero-motion')?.addEventListener('click', () => setMotion(!reduced));
const motionObserver = new IntersectionObserver(entries => entries.forEach(entry => {
  entry.target.classList.toggle('motion-visible', entry.isIntersecting);
}), {threshold:.15});
$$('.mac-showcase').forEach(element=>motionObserver.observe(element));
const previewObserver = new IntersectionObserver(entries => entries.forEach(entry => {
  if(!entry.isIntersecting || reduced || document.hidden) return;
  const button = entry.target.querySelector('.replay');
  if(button) button.click();
  previewObserver.unobserve(entry.target);
}), {threshold:.45});
if ($('.day-demo')) previewObserver.observe($('.day-demo'));
if ($('.presence-section')) previewObserver.observe($('.presence-section'));
document.addEventListener('visibilitychange',()=>document.documentElement.classList.toggle('page-hidden',document.hidden));

// Keep the four lettered cords attached to both the moving fingertips and Suzzme.
// The rig pauses offscreen, in background tabs, and for reduced motion.
const handRig = $('.hand-rig'), mascotRig = $('.mascot-rig');
const letterCords = $$('.letter-cord');
const fingertips = [[944,143],[1013,293],[1068,323],[1243,263]];
const attachments = [[985,681],[1060,555],[1160,555],[1250,681]];
const cordBaseLengths = [533, 260, 247, 416];
let rigVisible = false, rigRequest = 0, rigElapsed = 0, rigLast = 0;
function rotatePoint(point, origin, angle, dx = 0, dy = 0){
  const x = point[0]-origin[0], y = point[1]-origin[1];
  return [origin[0]+x*Math.cos(angle)-y*Math.sin(angle)+dx, origin[1]+x*Math.sin(angle)+y*Math.cos(angle)+dy];
}
function drawRig(seconds){
  const phase = seconds * Math.PI / 4;
  const handAngle = Math.sin(phase) * 1.7;
  const mascotAngle = Math.sin(phase-.55) * 8;
  const dx = Math.sin(phase-.55) * 35;
  const dy = Math.cos(phase*2) * 6;
  const mascotTransform = `translate(${dx} ${dy}) rotate(${mascotAngle} 1120 650)`;
  handRig.setAttribute('transform', `rotate(${handAngle} 1620 190)`);
  mascotRig.setAttribute('transform', mascotTransform);
  letterCords.forEach((cord,i)=>{
    const start=rotatePoint(fingertips[i],[1620,190],handAngle*Math.PI/180);
    const end=rotatePoint(attachments[i],[1120,650],mascotAngle*Math.PI/180,dx,dy);
    const length=Math.hypot(end[0]-start[0],end[1]-start[1]);
    const angle=Math.atan2(end[1]-start[1],end[0]-start[0])*180/Math.PI-90;
    const scaleY = length / cordBaseLengths[i];
    cord.setAttribute('transform',`translate(${start[0]} ${start[1]}) rotate(${angle}) scale(1 ${scaleY})`);
  });
}
function runRig(now){
  if(rigLast)rigElapsed+=(now-rigLast)/1000;
  rigLast=now;drawRig(rigElapsed);rigRequest=requestAnimationFrame(runRig);
}
function syncRig(){
  cancelAnimationFrame(rigRequest);rigRequest=0;rigLast=0;
  if(rigVisible && !reduced && !document.hidden)rigRequest=requestAnimationFrame(runRig);
}
new IntersectionObserver(entries=>{rigVisible=entries[0].isIntersecting;syncRig();},{threshold:.05}).observe($('.hero-art'));
$('#hero-motion').addEventListener('click',syncRig);
$('#motion-toggle')?.addEventListener('click',syncRig);
preference.addEventListener('change',syncRig);
document.addEventListener('visibilitychange',syncRig);
window.addEventListener('pagehide',()=>cancelAnimationFrame(rigRequest));
drawRig(0);

// Interactive Suzzme App Constellation / Orbit animation
(function initAppOrbitGalaxy() {
  const galaxy = $('.app-orbit-galaxy');
  const centerStage = $('.orbit-center-stage');
  const mascotBtn = $('.orbit-mascot-btn');
  const tracks = $$('.orbit-track');
  const badges = $$('.orbit-badge');

  if (!galaxy || !centerStage) return;

  // Click companion mascot for a playful hop and orbital pulse wave
  if (mascotBtn) {
    mascotBtn.addEventListener('click', () => {
      centerStage.classList.remove('bouncing');
      void centerStage.offsetWidth;
      centerStage.classList.add('bouncing');

      badges.forEach((badge, idx) => {
        setTimeout(() => {
          badge.style.transform = 'scale(1.22)';
          badge.style.borderColor = 'rgba(255, 255, 255, 0.8)';
          badge.style.boxShadow = '0 0 24px rgba(73, 163, 226, 0.7)';
          setTimeout(() => {
            badge.style.transform = '';
            badge.style.borderColor = '';
            badge.style.boxShadow = '';
          }, 350);
        }, idx * 45);
      });

      setTimeout(() => centerStage.classList.remove('bouncing'), 700);
    });
  }

  // Observe galaxy visibility to pause animation offscreen
  const galaxyObserver = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      const isVisible = entry.isIntersecting;
      tracks.forEach(track => {
        if (!isVisible || reduced) {
          track.classList.add('is-paused');
        } else {
          track.classList.remove('is-paused');
        }
      });
    });
  }, { threshold: 0.08 });

  galaxyObserver.observe(galaxy);

  function syncGalaxyMotion() {
    tracks.forEach(track => {
      if (reduced) {
        track.classList.add('is-paused');
      } else {
        track.classList.remove('is-paused');
      }
    });
  }

  $('#motion-toggle')?.addEventListener('click', syncGalaxyMotion);
  $('#hero-motion').addEventListener('click', syncGalaxyMotion);
  preference.addEventListener('change', syncGalaxyMotion);
})();
