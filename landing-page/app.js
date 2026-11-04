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
function renderDay(index, announce = false) {
  dayIndex = index;
  $$('[data-step]').forEach(button => { const active = Number(button.dataset.step) === index; button.setAttribute('aria-pressed', active); button.classList.toggle('active', active); });
  $('#day-content').innerHTML = dayViews[index];
  animateContent($('#day-content'));
  if (announce) $('#announcement').textContent = ['Your context: calendar, mail, and reminders.','Your Daily Summary is ready.','Your suggested plan is ready.'][index];
}
function stopDay() { clearTimeout(dayTimer); dayTimer = null; $('#play-day').textContent = '▶  Play the story'; }
$$('[data-step]').forEach(button => button.addEventListener('click', () => {stopDay();renderDay(Number(button.dataset.step), true);}));
$('#play-day').addEventListener('click', () => {
  if (dayTimer) { stopDay(); return; }
  renderDay(0, true); $('#play-day').textContent = 'Ⅱ  Pause the story';
  function next(){ if(dayIndex < 2){renderDay(dayIndex+1,true);dayTimer=setTimeout(next,3300);}else stopDay(); }
  dayTimer=setTimeout(next,3300);
});
const states = [
  {island:'Gathering your day',title:'Your day, coming together.',description:'Finding the important bits.',footer:'A little clarity is on its way',badge:'IN PROGRESS',progress:.3,symbol:'◌'},
  {island:'Connecting the dots',title:'A little space to think.',description:'Making sense of your context.',footer:'Looking at the bigger picture',badge:'THINKING',progress:.6,symbol:'⋯'},
  {island:'Your day, in a few words',title:'Let’s talk about your day.',description:'Your summary, read back to you.',footer:'A thoughtful start to your morning',badge:'SPEAKING',progress:.85,symbol:'≋'},
  {island:'Your summary is ready',title:'A good day starts here.',description:'Your summary and plan are ready.',footer:'Ready to continue in Suzzme',badge:'ALL READY',progress:1,symbol:'✓'}
];
function renderPresence(index, announce = false) {
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
  clearTimeout(cueTimer); $('.phone').classList.remove('cue');
  if(!reduced && index!==3){requestAnimationFrame(()=>{if(!document.hidden && !reduced)$('.phone').classList.add('cue');});cueTimer=setTimeout(()=>$('.phone').classList.remove('cue'),1400);}
  animateContent($('#live-activity'));
  if(announce)$('#announcement').textContent=state.title+' '+state.description;
}
function stopPresence(){clearTimeout(presenceTimer);presenceTimer=null;$('#play-presence').textContent='▶  Play companion sequence';}
$$('[data-state]').forEach(button=>button.addEventListener('click',()=>{stopPresence();renderPresence(Number(button.dataset.state),true);}));
$('#play-presence').addEventListener('click',()=>{
  if(presenceTimer){stopPresence();return;}
  renderPresence(0,true);$('#play-presence').textContent='Ⅱ  Pause companion sequence';
  function next(){if(presenceIndex<3){renderPresence(presenceIndex+1,true);presenceTimer=setTimeout(next,2600);}else stopPresence();}
  presenceTimer=setTimeout(next,2600);
});
$('#hero-play').addEventListener('click',()=>{
  clearTimeout(heroTimer);$('.hero-art').classList.remove('replaying');
  requestAnimationFrame(()=>$('.hero-art').classList.add('replaying'));
  $('#announcement').textContent='Meet Suzzme, your little companion for a clearer day.';
  heroTimer=setTimeout(()=>{$('.hero-art').classList.remove('replaying');$('#presence').scrollIntoView({behavior:reduced?'instant':'smooth'});},reduced?0:1200);
});
function setMotion(value){reduced=value;document.documentElement.classList.toggle('reduce-motion',value);$('#motion-toggle').textContent=value?'Motion reduced':'Motion on';$('#motion-toggle').setAttribute('aria-pressed',value);$('#hero-motion').textContent=value?'Resume motion':'Pause motion';$('#hero-motion').setAttribute('aria-pressed',value);document.getAnimations().forEach(animation=>{if(value && animation.effect?.target?.closest('#day-content, #live-activity'))animation.finish();});if(value){clearTimeout(cueTimer);$('.phone').classList.remove('cue');}}
$('#motion-toggle').addEventListener('click',()=>setMotion(!reduced));preference.addEventListener('change',event=>setMotion(event.matches));
document.addEventListener('visibilitychange',()=>{if(document.hidden){stopDay();stopPresence();clearTimeout(cueTimer);clearTimeout(heroTimer);$('.phone').classList.remove('cue');$('.hero-art').classList.remove('replaying');}});
const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');observer.unobserve(entry.target);}}),{threshold:.12});
$$('.section-heading,.day-demo,.presence-copy,.phone-stage,.principles article,.closing>h2').forEach(element=>{element.classList.add('reveal');observer.observe(element);});
setMotion(reduced);renderDay(0);renderPresence(0);
const sceneObserver = new IntersectionObserver(entries => {
  $('.hero-art').classList.toggle('scene-paused', !entries[0].isIntersecting || document.hidden);
}, { threshold: .1 });
sceneObserver.observe($('.hero-art'));
document.addEventListener('visibilitychange', () => {
  const rect = $('.hero-art').getBoundingClientRect();
  $('.hero-art').classList.toggle('scene-paused', document.hidden || rect.bottom <= 0 || rect.top >= innerHeight);
});

// Supplied Suzzme variants; original assets remain available in the repository.
$$('[data-mascot]').forEach(button => button.addEventListener('click', () => {
  const variant = button.dataset.mascot;
  $$('[data-mascot]').forEach(item => item.setAttribute('aria-pressed', item === button));
  $$('img[src^="assets/mascots/"]').filter(img => !img.closest('.mascot-family')).forEach(img => img.src = `assets/mascots/${variant}.png`);
  $('.mascot-art').setAttribute('href', `assets/mascots/${variant}.png`);
  $('#announcement').textContent = `${variant[0].toUpperCase()+variant.slice(1)} Suzzme selected.`;
}));
$('#hero-motion').addEventListener('click', () => setMotion(!reduced));
$$('[data-mac-view]').forEach(button => button.addEventListener('click', () => {
  const actual = button.dataset.macView === 'actual';
  $$('[data-mac-view]').forEach(item => item.setAttribute('aria-pressed', item === button));
  $('.mac-actual').hidden = !actual;
  $('.mac-live').hidden = actual;
  if(actual) stopDay();
}));
const motionObserver = new IntersectionObserver(entries => entries.forEach(entry => {
  entry.target.classList.toggle('motion-visible', entry.isIntersecting);
}), {threshold:.15});
$$('.mac-showcase,.mascot-family').forEach(element=>motionObserver.observe(element));
const previewObserver = new IntersectionObserver(entries => entries.forEach(entry => {
  if(!entry.isIntersecting || reduced || document.hidden) return;
  const button = entry.target.querySelector('.replay');
  if(button) button.click();
  previewObserver.unobserve(entry.target);
}), {threshold:.45});
previewObserver.observe($('.day-demo'));
previewObserver.observe($('.presence-section'));
document.addEventListener('visibilitychange',()=>document.documentElement.classList.toggle('page-hidden',document.hidden));

// Keep the four lettered cords attached to both the moving fingertips and Suzzme.
// The rig is decorative: it pauses offscreen, in background tabs, and for reduced motion.
const handRig = $('.hand-rig'), mascotRig = $('.mascot-rig');
const letterCords = $$('.letter-cord');
const fingertips = [[944,143],[1013,293],[1068,323],[1243,263]];
const attachments = [[985,681],[1060,555],[1160,555],[1250,681]];
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
  handRig.setAttribute('transform', `rotate(${handAngle} 1620 190)`);
  mascotRig.setAttribute('transform', `translate(${dx} ${dy}) rotate(${mascotAngle} 1120 650)`);
  letterCords.forEach((cord,i)=>{
    const start=rotatePoint(fingertips[i],[1620,190],handAngle*Math.PI/180);
    const end=rotatePoint(attachments[i],[1120,650],mascotAngle*Math.PI/180,dx,dy);
    const length=Math.hypot(end[0]-start[0],end[1]-start[1]);
    const angle=Math.atan2(end[1]-start[1],end[0]-start[0])*180/Math.PI-90;
    cord.setAttribute('transform',`translate(${start[0]} ${start[1]}) rotate(${angle}) scale(1 ${length/384})`);
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
$('#motion-toggle').addEventListener('click',syncRig);
preference.addEventListener('change',syncRig);
document.addEventListener('visibilitychange',syncRig);
window.addEventListener('pagehide',()=>cancelAnimationFrame(rigRequest));
drawRig(0);
