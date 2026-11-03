const $ = (s, root = document) => root.querySelector(s);
const $$ = (s, root = document) => [...root.querySelectorAll(s)];
const concepts = [
  {id:'companion',name:'Companion',tag:'PERSONAL',title:'A familiar face. A quiet update.',description:'Character led, with a single clear progress signal.'},
  {id:'briefing',name:'Briefing',tag:'EDITORIAL',title:'Your day, distilled.',description:'A typographic approach that puts meaning first.'},
  {id:'focus',name:'Focus',tag:'PRECISE',title:'Less noise. More signal.',description:'Structured source status, reduced to the essentials.'}
];
const mascot = '<img class="mascot" src="assets/mascot.png" alt="">';
const ring = '<svg class="ring" viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="13"/><circle class="ring-value" cx="16" cy="16" r="13" stroke-dasharray="81.682" stroke-dashoffset="47"/></svg>';
const signal = '<span class="signal" aria-hidden="true">'+ '<i></i>'.repeat(7)+'</span>';
$('#gallery').innerHTML = concepts.map((c,index) => `<article class="concept ${c.id}" data-concept="${c.id}">
  <div class="concept-top"><div class="concept-title"><span class="concept-number">0${index+1}</span>${c.name}</div><span class="concept-tag">${c.tag}</span></div>
  <div class="device-wrap"><div class="device"><div class="screen expanded">
    <div class="wallpaper"></div><div class="statusbar"><span>9:41</span><span class="status-icons">▂▄▆ <span>◒</span><i class="battery"></i></span></div>
    <div class="home-content"><div class="day">Tuesday, November 3</div><div class="clock">9:41</div><div class="home-widget"><div class="small-label">A LITTLE SPACE FOR YOUR DAY</div><h4>Room to focus.</h4><p>Your next meeting is at 11.<br>Until then, make it yours.</p><div class="widget-bottom"><span>◷ 1 hr 19 min free</span><span>↗</span></div></div><div class="app-row">${['◷','▤',mascot,'◎'].map((v,i)=>`<div><div class="app-tile">${v}</div><div class="app-name">${['Calendar','Notes','Suzzme','Photos'][i]}</div></div>`).join('')}</div></div>
    <div class="dock" aria-hidden="true"><i>⌕</i><i>◈</i><i>▰</i><i>♫</i></div><div class="home-indicator"></div>
    <div class="app-destination"><button class="back-home">‹ Home Screen</button><small>SUZZME / DAILY SUMMARY</small><h3>Your day,<br>understood.</h3><p class="destination-status">Your summary is coming together.</p><div class="summary-detail"><small>ILLUSTRATIVE PREVIEW</small><p>You have room to focus before your 11 am meeting.</p><p>Your project notes are ready to review. Two follow-ups can wait until this afternoon.</p></div></div>
    <div class="island-root"><div class="island-surface"></div><div class="camera"></div>
      <div class="island-content"><div class="island-header">${index===0?mascot:index===1?'<span class="brief-icon">▤</span>':signal}<span class="right-label">${index===1?'DAILY BRIEFING':'SUZZME'}</span></div>
      <div class="island-main"><h3 class="island-title">${index===1?'Your day, taking shape.':'Finding the connections'}</h3><p class="island-subtitle">${index===2?'Your sources, working together.':'A little context. A clearer day.'}</p></div>
      ${index===0?'<div class="progress-track"><div class="progress-fill"></div></div>':index===1?'<div class="milestones"><span></span><span></span><span></span><span></span></div>':'<div class="source-list"><div class="source-line"><span>▦ Calendar</span><b>Gathered ✓</b></div><div class="source-line"><span>▤ Notes</span><span class="notes-status">Reading…</span></div><div class="source-line"><span>✉ Mail</span><span class="mail-status">Next up</span></div></div>'}
      <div class="island-bottom">${index===0?'<span class="sources"><b>▦</b><b>▤</b><b>✉</b><span>3 sources</span></span>':`<span class="bottom-status">${index===1?'3 sources · One clear view':'Gathering context'}</span>`}<button class="island-action">Cancel</button></div>
      </div>
      <div class="compact-row">${index===0?mascot:index===1?'<span class="brief-icon">▤</span>':signal}<span class="compact-value">${index===1?'3':ring}</span></div>
      <div class="minimal-bubble">${ring}${mascot}</div>
      <button class="island-trigger" aria-label="${c.name}: tap to open Suzzme, hold to expand" title="Tap to open · Hold to expand"></button>
    </div>
  </div></div></div><div class="device-caption">iPHONE 18 PRO / SILVER</div><p class="concept-description"><strong>${c.title}</strong>${c.description}</p>
</article>`).join('');

let progress = 42, running = false, mode = 'expanded', speed = 1, lastTime = 0, lastRendered = -1, lastPhase = '';
let lifecycle = 'active';
const systemMotion = matchMedia('(prefers-reduced-motion: reduce)');
$('#reduce').checked = systemMotion.matches;
function phase() { return lifecycle==='idle'?'idle':lifecycle==='cancelled'?'cancelled':progress>=100?'ready':progress<30?'gathering':progress<70?'understanding':'summarizing'; }
const labels = {idle:'Ready when you are',cancelled:'Summary cancelled',gathering:'Gathering your context',understanding:'Finding the connections',summarizing:'Making it clear',ready:'Your summary is ready'};
function setMode(next) {
  mode=next;
  $$('.screen').forEach(el=>{el.classList.remove('minimal','compact','expanded');el.classList.add(mode)});
  $$('.island-content').forEach(el=>{el.inert=mode!=='expanded';el.setAttribute('aria-hidden',String(mode!=='expanded'));});
  $$('#modes button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.mode===mode)));
  $('#mode-hint').textContent = {minimal:'A live indicator when the island is shared.',compact:'Essential status on either side of the camera.',expanded:'More context, revealed with a touch and hold.'}[mode];
}
function render() {
  const p=phase(), ready=p==='ready', idle=p==='idle'||p==='cancelled', value=Math.round(progress);
  $('#progress').value=value;$('#progress-value').textContent=idle?'—':`${value}%`;
  $('#play').textContent=running?'Ⅱ Pause':progress>=100?'↻ Replay':'▶ Play';
  $('#phase-label').textContent=labels[p];
  $('#phase-description').textContent={idle:'Start a new summary session.',cancelled:'Start again whenever you like.',gathering:'Reading 3 selected sources.',understanding:'Bringing your sources together.',summarizing:'Turning context into a clear view.',ready:'A calm view of what matters.'}[p];
  document.body.classList.toggle('paused',!running);document.body.classList.toggle('ready',ready);
  $$('.concept').forEach((el,i)=>{
    $('.island-root',el).style.visibility=idle?'hidden':'visible';
    $('.island-root',el).inert=idle;
    $('.island-trigger',el).setAttribute('aria-label',`${concepts[i].name}: ${labels[p]}, ${value} percent. Tap to open Suzzme, hold to expand`);
    $('.island-title',el).textContent = i===1?(ready?'Your day, understood.':progress<30?'A little context first.':progress<70?'Your day, taking shape.':'The things that matter.'):i===2?(ready?'All together. All clear.':labels[p]):labels[p];
    $('.island-subtitle',el).textContent=ready?(i===1?'3 sources. The essentials, connected.':'Your day, distilled into the essentials.'):(i===2?'Your sources, working together.':progress<30?'Reading the sources you chose.':progress<70?'A little context. A clearer day.':'Pulling the essentials together.');
    $$('.ring-value',el).forEach(r=>r.style.strokeDashoffset=81.682*(1-progress/100));
    const fill=$('.progress-fill',el);if(fill)fill.style.transform=`scaleX(${progress/100})`;
    const compact=$('.compact-value',el);if(i!==0)compact.textContent=ready?'✓':i===1?'3':`${value}%`;
    $$('.milestones span',el).forEach((s,j)=>s.classList.toggle('done',progress>j*25));
    const notes=$('.notes-status',el), mail=$('.mail-status',el);
    if(notes){notes.textContent=progress>=40?'Understood ✓':'Reading…';mail.textContent=progress>=75?'Understood ✓':progress>=40?'Reading…':'Next up';}
    const bottom=$('.bottom-status',el);if(bottom)bottom.textContent=ready?'3 sources · Summary ready':i===1?'3 sources · One clear view':`${value}% · ${progress<30?'Gathering':progress<70?'Understanding':'Summarizing'}`;
    $('.island-action',el).textContent=ready?'Read summary ↗':'Cancel';
    $('.destination-status',el).textContent=ready?'Here’s what matters today.':idle?'Start a summary to connect your day.':'Your summary is coming together.';
    $('.summary-detail',el).hidden=!ready;
    $$('.signal i',el).forEach((bar,j)=>{bar.style.opacity=ready?'1':progress>(j/7)*100?'1':'.25';bar.style.transform=ready?'scaleY(.7)':`scaleY(${.55+((Math.floor(progress/8)+j)%4)*.15})`;});
  });
  if(lastPhase!==p){$('#announcement').textContent=labels[p];lastPhase=p;}
}
function reset(){running=false;progress=0;lifecycle='idle';$$('.app-destination').forEach(e=>e.classList.remove('visible'));render();}
function start(){$$('.app-destination').forEach(e=>e.classList.remove('visible'));progress=0;lifecycle='active';running=true;lastTime=performance.now();render();}
function tick(now){if(running&&!document.hidden){progress=Math.min(100,progress+(now-lastTime)/160*speed);if(progress>=100)running=false;if(Math.floor(progress)!==lastRendered){render();lastRendered=Math.floor(progress);}}lastTime=now;requestAnimationFrame(tick);}
$('#summarize').addEventListener('click',start);
$('#reset').addEventListener('click',reset);
$('#play').addEventListener('click',()=>{if(progress>=100){start();return;}lifecycle='active';running=!running;lastTime=performance.now();render();});
$('#progress').addEventListener('input',e=>{running=false;lifecycle='active';progress=Number(e.target.value);render();});
$('#speed').addEventListener('change',e=>{speed=Number(e.target.value);});
$('#reduce').addEventListener('change',e=>document.body.classList.toggle('reduce-motion',e.target.checked));
systemMotion.addEventListener('change',e=>{$('#reduce').checked=e.matches;document.body.classList.toggle('reduce-motion',e.matches);});
$('#night').addEventListener('change',e=>document.body.classList.toggle('night',e.target.checked));
$$('#modes button').forEach(b=>b.addEventListener('click',()=>setMode(b.dataset.mode)));
$$('.concept').forEach(el=>{
  const trigger=$('.island-trigger',el);let holdTimer,held=false;
  const open=()=>{setMode('compact');$('.app-destination',el).classList.add('visible');$('.back-home',el).focus();$('#announcement').textContent='Suzzme summary destination preview opened';};
  trigger.addEventListener('pointerdown',()=>{held=false;holdTimer=setTimeout(()=>{held=true;setMode('expanded');},450);});
  ['pointerup','pointercancel','pointerleave'].forEach(type=>trigger.addEventListener(type,()=>clearTimeout(holdTimer)));
  trigger.addEventListener('click',()=>{if(!held)open();held=false;});
  trigger.addEventListener('keydown',e=>{if(e.key==='ArrowDown'){e.preventDefault();setMode('expanded');}});
  $('.back-home',el).addEventListener('click',()=>{$('.app-destination',el).classList.remove('visible');trigger.focus();});
  $('.island-action',el).addEventListener('click',()=>{if(progress>=100)open();else{running=false;lifecycle='cancelled';render();}});
});
document.addEventListener('visibilitychange',()=>{lastTime=performance.now();});
document.body.classList.toggle('reduce-motion',$('#reduce').checked);
setMode(mode);render();requestAnimationFrame(tick);
