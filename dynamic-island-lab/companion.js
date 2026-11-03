'use strict';
// Design-only session playback. Native assistant state and data remain untouched.
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const icon = name => `<svg aria-hidden="true"><use href="#icon-${name}"/></svg>`;
const character = '<img class="character" src="assets/mascot.png" alt="">';
const ring = '<svg class="snapshot-ring" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5" stroke="currentColor" opacity=".25"/><path d="M12 3.5a8.5 8.5 0 0 1 8.5 8.5" stroke="currentColor"/></svg>';
const sessionStates = {
  idle: {title:'Ready when you are',detail:'A little space to understand your day.',widget:['Make sense','of your day.'],label:'Tap to begin',symbol:'sun',at:0},
  summarizing: {title:'Summarizing your day',detail:'Bringing your chosen context together.',widget:['Your day,','taking shape.'],label:'Summarizing',symbol:'note',at:4},
  thinking: {title:'Finding the connections',detail:'A little context. A clearer day.',widget:['Connecting','the dots.'],label:'Thinking',symbol:'think',at:9},
  speaking: {title:'Reading your day aloud',detail:'Your briefing, spoken with care.',widget:['A little','perspective.'],label:'Speaking',symbol:'wave',at:14},
  ready: {title:'Your summary is ready',detail:'The essentials, together in one place.',widget:['Your day,','understood.'],label:'Ready to read',symbol:'check',at:20}
};
function activityMarkup() {
  return `<div class="activity" data-state="summarizing" role="group" aria-label="Suzzme session Live Activity">
    <div class="activity-top">${character}<span class="surface-brand">Suzzme</span><span class="activity-status"><i class="status-light"></i><span>42%</span></span></div>
    <h3 class="activity-title">Summarizing your day</h3><p class="surface-description">Bringing your chosen context together.</p>
    <div class="activity-meter" aria-hidden="true"><div class="meter-fill"></div></div>
    <div class="activity-bottom"><div class="activity-metadata"><span class="source-symbols" aria-hidden="true"><i>${icon('calendar')}</i><i>${icon('note')}</i><i>${icon('mail')}</i></span><span class="activity-indicator" aria-hidden="true">${'<i></i>'.repeat(7)}</span><span class="metadata-label">3 sources</span></div><button class="surface-action" aria-label="Cancel summary">Cancel</button></div>
  </div><div class="idle-placeholder" hidden>${icon('cloud')}<span>No active Live Activity</span><small>Start a session to preview its Lock Screen presentation.</small></div>`;
}
function widgetMarkup() {
  return `<button class="small-widget" aria-label="Open Suzzme summary" data-state="summarizing"><span class="widget-top">${character}<span class="widget-status-icon">${ring}</span></span><span class="widget-title">Your day,<br>taking shape.</span><span class="widget-label"><i></i><span>Summarizing</span></span></button>`;
}
function appIcon(name, symbol, extra='') {
  return `<div class="app-icon"><span class="icon-art ${extra}">${symbol}</span><span>${name}</span></div>`;
}
const status = `<div class="phone-status"><span>9:41</span><span class="status-trailing"><span class="cell-signal" aria-hidden="true"><i></i><i></i><i></i><i></i></span><span aria-hidden="true">◓</span><i class="battery" aria-hidden="true"></i></span></div>`;
const destination = `<div class="destination" inert><button class="back">‹ Back to preview</button><small>SUZZME / APP DESTINATION PREVIEW</small><h3>Your day,<br>understood.</h3><p class="destination-status">Your summary is coming together.</p><div class="sample-details"><small>FICTIONAL SUMMARY</small><p>A little room to focus this morning. Your next meeting is at 11.</p><p>Two follow-ups can wait until this afternoon. Your project notes are ready to review.</p></div><button class="destination-start">Summarize my day ${icon('arrow')}</button></div>`;
function phoneMarkup(type) {
  const lock = type==='lock';
  return `<div class="hardware"><i class="side-button"></i><i class="side-button"></i><i class="side-button"></i><i class="side-button"></i><div class="display ${lock?'lock-display':'home-display'}">
    <div class="wallpaper"></div><div class="camera"></div>${lock?'':status}
    ${lock?`<div class="lock-identity">${icon('lock')}<div class="lock-date">Tuesday, November 3</div><div class="lock-clock">9:41</div><div class="lock-accessories"><span class="weather-accessory">${icon('sun')}24°</span><span class="accessory-divider"></span><span class="date-accessory">A LITTLE SPACE<strong>To make it yours</strong></span></div></div><div class="lock-focus"><span>${icon('cloud')}A moment for your day</span></div><div class="live-region">${activityMarkup()}</div><div class="lock-actions" aria-hidden="true"><span>${icon('torch')}</span><span>${icon('camera')}</span></div><div class="swipe-label">Swipe up to open</div>`:`<div class="home-layout"><div class="small-widget-slot">${widgetMarkup()}<span class="widget-name">Suzzme</span></div><div class="app-quartet">${appIcon('Calendar','<small>TUE</small><strong>3</strong>','calendar-art')}${appIcon('Notes',icon('note'),'notes-art')}${appIcon('Photos','✿','photos-art')}${appIcon('Weather',icon('sun'))}</div><div class="app-row">${appIcon('Mail',icon('mail'))}${appIcon('Suzzme',character)}${appIcon('Reminders',icon('note'))}${appIcon('Camera',icon('camera'))}</div><div class="quiet-widget"><small>TUESDAY, AT YOUR PACE</small><h4>Room to focus.</h4><p>Some things can wait.<br>Make space for what matters.</p></div></div><span class="home-search">⌕ Search</span><div class="dock" aria-hidden="true"><span class="icon-art">${icon('phone')}</span><span class="icon-art">${icon('compass')}</span><span class="icon-art">${icon('mail')}</span><span class="icon-art">${icon('music')}</span></div>`}
    ${destination}<div class="home-indicator"></div>
  </div></div>`;
}
$('#lock-phone').innerHTML=phoneMarkup('lock');
$('#home-phone').innerHTML=phoneMarkup('home');
$('#activity-detail').innerHTML=activityMarkup();
$('#widget-detail').innerHTML=widgetMarkup();

let current='summarizing', time=4, running=false, speed=1, lastFrame=0, lastPaint=0, playbackPaused=false;
let snapshot='summarizing', snapshotCount=0;
const finiteAnimations=new Set();
const reducedQuery=matchMedia('(prefers-reduced-motion: reduce)');
$('#reduce').checked=reducedQuery.matches;
function motionAllowed(){return !$('#reduce').checked&&!$('#always-on').checked&&!reducedQuery.matches;}
function cancelMotion(){finiteAnimations.forEach(a=>a.cancel());finiteAnimations.clear();}
function animate(element,frames,options){
  if(!motionAllowed())return;
  const animation=element.animate(frames,options);
  finiteAnimations.add(animation);
  animation.finished.then(()=>finiteAnimations.delete(animation)).catch(()=>finiteAnimations.delete(animation));
}
function contentCue(){
  cancelMotion();
  if(!motionAllowed()||document.hidden)return;
  $$('.activity-title,.widget-title').forEach(el=>animate(el,[{opacity:.5},{opacity:1}],{duration:250,easing:'cubic-bezier(.23,1,.32,1)'}));
  $$('.activity .character,.small-widget .character').forEach(el=>{
    const frames=current==='thinking'?[{transform:'scale(1.25) rotate(0deg)'},{transform:'scale(1.22) rotate(-4deg)',offset:.4},{transform:'scale(1.25) rotate(0deg)'}]:current==='speaking'?[{transform:'scale(1.25) translateY(0)'},{transform:'scale(1.28) translateY(-1px)',offset:.3},{transform:'scale(1.25) translateY(0)',offset:.65},{transform:'scale(1.27) translateY(-.5px)',offset:.8},{transform:'scale(1.25) translateY(0)'}]:[{opacity:.75},{opacity:1}];
    animate(el,frames,{duration:current==='thinking'||current==='speaking'?1200:250,easing:'cubic-bezier(.77,0,.175,1)'});
  });
  $$('.activity[data-state=speaking] .activity-indicator i').forEach((el,i)=>animate(el,[{transform:'scaleY(.5)'},{transform:`scaleY(${i%2?.6:1.2})`,offset:.35},{transform:'scaleY(.65)',offset:.65},{transform:'scaleY(1)'}],{duration:1100,delay:i*12,easing:'cubic-bezier(.77,0,.175,1)'}));
  $$('.activity[data-state=thinking] .activity-indicator').forEach(group=>$$('i',group).slice(0,3).forEach((el,i)=>animate(el,[{opacity:.3},{opacity:1,offset:.4},{opacity:.5}],{duration:900,delay:i*100,easing:'cubic-bezier(.77,0,.175,1)'})));
}
function stateAt(t){return t>=20?'ready':t<7?'summarizing':t<12?'thinking':'speaking';}
function refreshSnapshot(animateUpdate=false){
  snapshot=current;snapshotCount++;
  const state=sessionStates[snapshot];
  $$('.small-widget').forEach(el=>{
    el.dataset.state=snapshot;el.classList.toggle('widget-ready',snapshot==='ready');
    $('.widget-title',el).innerHTML=state.widget.join('<br>');
    $('.widget-label span',el).textContent=state.label;
    $('.widget-status-icon',el).innerHTML=snapshot==='summarizing'?ring:icon(state.symbol);
    el.setAttribute('aria-label',`Suzzme widget: ${state.label}. Open ${snapshot==='ready'?'summary':'session'} in Suzzme`);
  });
  $('#snapshot-label').textContent=`Timeline snapshot · ${String(snapshotCount).padStart(2,'0')}`;
  if(animateUpdate)contentCue();
}
function render(){
  const state=sessionStates[current], ended=current==='ready'||current==='idle';
  const progress=current==='summarizing'||current==='thinking'?Math.round(time/12*100):current==='speaking'?Math.round((time-12)/8*100):current==='ready'?100:0;
  document.body.dataset.state=current;
  $('#timeline').value=Math.round(time*10);$('#elapsed').textContent=`00:${String(Math.floor(time)).padStart(2,'0')} / 00:20`;
  $('#play span').textContent=running?'Pause sequence':time>=20?'Replay full sequence':playbackPaused?'Resume sequence':'Play full sequence';
  $('#play use').setAttribute('href',running?'#icon-pause':'#icon-play');
  $$('#states button').forEach(el=>el.setAttribute('aria-pressed',String(el.dataset.state===current)));
  $('#status-title').textContent=state.title;
  $('#status-detail').textContent=$('#always-on').checked?'Lock Screen dimmed · Motion stays still.':current==='ready'?'Session ended · Completed card retained briefly.':current==='idle'?'Start a moment or play the full sequence.':running?'Playing a 20 second illustrative session.':'A still moment. Replay to inspect its motion.';
  $$('.activity').forEach(el=>{
    el.dataset.state=current;el.hidden=current==='idle';
    const placeholder=el.nextElementSibling;placeholder.hidden=current!=='idle';
    $('.activity-title',el).textContent=state.title;
    $('.surface-description',el).textContent=state.detail;
    $('.activity-status>span',el).textContent=current==='ready'?'Complete':current==='speaking'?'Speaking':current==='thinking'?'Thinking':`${progress}%`;
    $('.meter-fill',el).style.transform=`scaleX(${progress/100})`;
    $('.source-symbols',el).hidden=current==='thinking'||current==='speaking';
    $('.activity-indicator',el).hidden=current!=='thinking'&&current!=='speaking';
    $('.metadata-label',el).textContent=current==='speaking'?`0:${String(Math.floor(time-12)).padStart(2,'0')} / 0:08`:current==='thinking'?'Understanding':'3 chosen sources';
    const action=$('.surface-action',el);
    action.innerHTML=current==='ready'?`Read summary ${icon('arrow')}`:current==='speaking'?`Stop ${icon('pause')}`:'Cancel';
    action.setAttribute('aria-label',current==='ready'?'Read summary in Suzzme':current==='speaking'?'Stop speaking':'Cancel summary');
    el.setAttribute('aria-label',`Suzzme Live Activity: ${state.title}${ended?'':`, ${progress} percent`}`);
  });
  $$('.sample-details').forEach(el=>el.hidden=current!=='ready');
  $$('.destination-start').forEach(el=>el.hidden=current!=='idle');
  $$('.destination-status').forEach(el=>el.textContent=current==='ready'?'Here’s what matters today.':current==='idle'?'Ask Suzzme to bring your day together.':state.title+'.');
}
function closeDestinations(){$$('.destination').forEach(el=>{el.classList.remove('visible');el.inert=true;el.closest('.display').classList.remove('destination-open');});$$('.live-region,.home-layout').forEach(el=>el.inert=false);}
function setMoment(next,{play=false,cue=true}={}){
  closeDestinations();current=next;time=play?0:sessionStates[next].at;running=play;playbackPaused=false;lastFrame=performance.now();
  refreshSnapshot();render();if(cue)contentCue();else cancelMotion();
  $('#announcement').textContent=sessionStates[next].title;
}
function tick(now){
  if(running&&!document.hidden){
    time=Math.min(20,time+(now-lastFrame)/1000*speed);
    const next=stateAt(time);
    if(next!==current){current=next;refreshSnapshot();render();contentCue();$('#announcement').textContent=sessionStates[current].title;}
    if(time>=20){running=false;render();}
    if(now-lastPaint>100){render();lastPaint=now;}
  }
  lastFrame=now;requestAnimationFrame(tick);
}
$$('#states button').forEach(el=>el.addEventListener('click',()=>setMoment(el.dataset.state)));
$('#play').addEventListener('click',()=>{
  if(running){running=false;playbackPaused=true;cancelMotion();render();return;}
  closeDestinations();
  if(!playbackPaused||time>=20||current==='idle'){time=0;current='summarizing';refreshSnapshot();}
  running=true;lastFrame=performance.now();render();contentCue();
});
$('#replay').addEventListener('click',()=>{if(current==='idle')setMoment('summarizing');else setMoment(current);});
$('#reset').addEventListener('click',()=>setMoment('idle',{cue:false}));
$('#timeline').addEventListener('input',e=>{
  running=false;playbackPaused=true;time=Number(e.target.value)/10;const next=stateAt(time),changed=next!==current;current=next;
  closeDestinations();if(changed)refreshSnapshot();render();cancelMotion();
});
$('#timeline').addEventListener('change',()=>{refreshSnapshot();render();contentCue();$('#announcement').textContent=sessionStates[current].title;});
$('#speed').addEventListener('change',e=>{speed=Number(e.target.value);});
$('#refresh-widget').addEventListener('click',()=>{refreshSnapshot(true);$('#announcement').textContent='Widget timeline snapshot refreshed: '+sessionStates[snapshot].label;});
$$('#appearance button').forEach(el=>el.addEventListener('click',()=>{
  document.body.classList.toggle('light-surfaces',el.dataset.appearance==='light');
  $$('#appearance button').forEach(b=>b.setAttribute('aria-pressed',String(b===el)));
}));
[['always-on','always-on'],['reduce','reduce-motion'],['large-type','large-type'],['contrast','high-contrast']].forEach(([id,cls])=>$('#'+id).addEventListener('change',e=>{document.body.classList.toggle(cls,e.target.checked);cancelMotion();render();}));
reducedQuery.addEventListener('change',e=>{$('#reduce').checked=e.matches;document.body.classList.toggle('reduce-motion',e.matches);cancelMotion();});
function openDestination(phone,trigger){
  const destination=$('.destination',phone);destination.inert=false;destination.classList.add('visible');destination.closest('.display').classList.add('destination-open');destination.returnFocus=trigger;$('.back',destination).focus();
  $$('.live-region,.home-layout',phone).forEach(el=>el.inert=true);
  $('#announcement').textContent='App destination preview opened. A real Lock Screen requires authentication before showing private content.';
}
$$('.phone-mount').forEach(phone=>{
  $$('.small-widget,.surface-action',phone).forEach(trigger=>trigger.addEventListener('click',()=>{
    if(trigger.classList.contains('surface-action')&&current!=='ready'){setMoment('idle',{cue:false});return;}
    openDestination(phone,trigger);
  }));
  $('.back',phone).addEventListener('click',()=>{const el=$('.destination',phone);closeDestinations();el.returnFocus?.focus();});
  $('.destination-start',phone).addEventListener('click',()=>{setMoment('summarizing',{play:true});});
});
$('#activity-detail .surface-action').addEventListener('click',e=>{if(current==='ready')openDestination($('#lock-phone'),e.currentTarget);else setMoment('idle',{cue:false});});
$('#widget-detail .small-widget').addEventListener('click',e=>openDestination($('#home-phone'),e.currentTarget));
document.addEventListener('keydown',e=>{if(e.key==='Escape'){const open=$('.destination.visible');closeDestinations();open?.returnFocus?.focus();}});
document.addEventListener('visibilitychange',()=>{lastFrame=performance.now();if(document.hidden)cancelMotion();});
document.body.classList.toggle('reduce-motion',$('#reduce').checked);
refreshSnapshot();render();requestAnimationFrame(tick);
