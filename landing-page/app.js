/* -------------------------------------------------------------
 * Suzzme — Interactive Landing Page Script
 * Powers the 8:00 AM Simulator, Audio Player & Micro-interactions
 * ------------------------------------------------------------- */

document.addEventListener('DOMContentLoaded', () => {
  // Scenario Data State
  const scenarios = {
    morning: {
      time: '8:00 AM',
      title: 'Suzzme — Tuesday, 8:00 AM Morning Briefing',
      quote: '"Hey Rehan, how are you doing? Here is your summary and plan for today..."',
      summary: {
        greeting: 'Good morning, Rehan. You have 3 meetings and 1 priority focus block today.',
        text: 'Your first meeting starts at 10:30 AM with the design team. Sarah sent an email regarding the Q4 sign-off that needs review. Lunch with family at 1:00 PM is confirmed on WhatsApp.',
        stats: [
          { label: 'Meetings', val: '3 scheduled' },
          { label: 'Priority Action', val: 'Sarah sign-off' },
          { label: 'Focus Window', val: '75 min before 10:30' },
          { label: 'Sources Synced', val: 'Calendar, Mail, WhatsApp' }
        ]
      },
      plan: [
        {
          time: '9:00 AM – 10:15 AM',
          type: 'focus',
          title: 'Deep Focus: Review PR #14 & Architecture Plan',
          note: 'Clear uninterrupted window before your team sync.'
        },
        {
          time: '10:30 AM – 11:30 AM',
          type: 'meeting',
          title: 'Design Team Sync · macOS & iOS Experience',
          note: 'Google Meet link verified in Calendar.'
        },
        {
          time: '1:00 PM – 2:00 PM',
          type: 'personal',
          title: 'Lunch with Family',
          note: 'Location confirmed via WhatsApp local chat.'
        },
        {
          time: '2:30 PM – 3:15 PM',
          type: 'task',
          title: 'Review and reply to Sarah’s project sign-off',
          note: 'Gmail header flagged as urgent priority.'
        }
      ],
      sources: [
        { name: 'Apple Calendar', status: '3 events today', desc: 'Read via EventKit' },
        { name: 'Apple Reminders', status: '2 tasks due', desc: 'Read via EventKit' },
        { name: 'WhatsApp for Mac', status: '1 chat synced', desc: 'Local selected folder only' },
        { name: 'Gmail Metadata', status: '2 urgent headers', desc: 'Sender & subject only' }
      ],
      island: {
        title: '8:00 AM · Summary Ready',
        desc: '3 meetings · 2 urgent emails · Plan ready'
      }
    },
    midday: {
      time: '1:00 PM',
      title: 'Suzzme — Tuesday, 1:00 PM Midday Catch-up',
      quote: '"Here is your midday check-in: Design sync is complete, next up is Sarah’s sign-off at 2:30 PM."',
      summary: {
        greeting: 'Midday update: Morning commitments completed smoothly.',
        text: 'Design sync finished on time. Next priority is Sarah’s sign-off reply at 2:30 PM. Your afternoon remains open for deep work after 3:30 PM.',
        stats: [
          { label: 'Meetings Left', val: '1 remaining' },
          { label: 'Tasks Done', val: 'PR #14 reviewed' },
          { label: 'Next Focus', val: 'Sarah reply at 2:30' },
          { label: 'Energy', val: 'Calm schedule' }
        ]
      },
      plan: [
        {
          time: '1:00 PM – 2:00 PM',
          type: 'personal',
          title: 'Lunch with Family (In progress)',
          note: 'Enjoy your break.'
        },
        {
          time: '2:30 PM – 3:15 PM',
          type: 'task',
          title: 'Review & Send Project Sign-off to Sarah',
          note: 'Draft response ready in Mail.'
        },
        {
          time: '3:30 PM – 5:30 PM',
          type: 'focus',
          title: 'Open Focus Block: iOS WidgetKit Polish',
          note: 'No interruptions scheduled.'
        }
      ],
      sources: [
        { name: 'Apple Calendar', status: '1 meeting left', desc: 'Updated 5m ago' },
        { name: 'Apple Reminders', status: '1 completed', desc: 'Updated 5m ago' },
        { name: 'WhatsApp for Mac', status: 'No new unread', desc: 'Local folder' },
        { name: 'Gmail Metadata', status: 'No new urgent', desc: 'Headers only' }
      ],
      island: {
        title: '1:00 PM · Midday Update',
        desc: '1 meeting left · Sign-off reply at 2:30 PM'
      }
    },
    evening: {
      time: '7:00 PM',
      title: 'Suzzme — Tuesday, 7:00 PM Evening Wrap-Down',
      quote: '"Great work today Rehan. You completed 4 tasks, and tomorrow starts at 10:00 AM."',
      summary: {
        greeting: 'Good evening. All scheduled commitments are complete for today.',
        text: 'PR #14 was approved and merged. Sarah’s sign-off was sent. Tomorrow’s earliest commitment is at 10:00 AM, leaving your morning free.',
        stats: [
          { label: 'Tasks Completed', val: '4 of 4 verified' },
          { label: 'Tomorrow Starts', val: '10:00 AM' },
          { label: 'Evening', val: 'Rest & unbind' },
          { label: 'State', val: 'All clear' }
        ]
      },
      plan: [
        {
          time: '7:00 PM – 8:00 PM',
          type: 'personal',
          title: 'Evening Walk & Wind Down',
          note: 'Work notifications muted.'
        },
        {
          time: 'Tomorrow, 8:00 AM',
          type: 'focus',
          title: 'Scheduled: Morning Briefing & Day Plan',
          note: 'Suzzme will prepare next day context at 8 AM.'
        }
      ],
      sources: [
        { name: 'Apple Calendar', status: 'Day complete', desc: 'EventKit' },
        { name: 'Apple Reminders', status: 'All done', desc: 'EventKit' },
        { name: 'WhatsApp for Mac', status: 'Quiet', desc: 'Local folder' },
        { name: 'Gmail Metadata', status: 'Inbox calm', desc: 'Headers only' }
      ],
      island: {
        title: '7:00 PM · Day Complete',
        desc: '4 tasks finished · Tomorrow starts 10 AM'
      }
    }
  };

  let currentScenarioKey = 'morning';
  let currentTabKey = 'plan';
  let isPlayingAudio = false;
  let audioTimer = null;
  let elapsedSeconds = 0;

  // DOM Elements
  const scenarioPills = document.querySelectorAll('.scenario-pill');
  const tabBtns = document.querySelectorAll('.tab-btn');
  const windowBody = document.getElementById('window-body');
  const windowScenarioTitle = document.getElementById('window-scenario-title');
  const audioQuote = document.getElementById('audio-quote');
  const audioToggle = document.getElementById('audio-toggle');
  const audioWaves = document.getElementById('audio-waves');
  const audioTime = document.getElementById('audio-time');
  const listenHeroBtn = document.getElementById('listen-briefing-btn');
  const listenHeroText = document.getElementById('listen-text');
  const islandLabel = document.getElementById('island-state-label');
  const lockTitle = document.getElementById('lock-title');
  const lockDesc = document.getElementById('lock-desc');
  const interactiveIsland = document.getElementById('interactive-island');

  // Render Window Content
  function renderWindow() {
    const data = scenarios[currentScenarioKey];
    windowScenarioTitle.textContent = data.title;
    audioQuote.textContent = data.quote;
    islandLabel.textContent = data.island.title;
    lockTitle.textContent = `${data.time} Briefing`;
    lockDesc.textContent = data.island.desc;

    if (currentTabKey === 'plan') {
      let html = '<div class="plan-timeline">';
      data.plan.forEach(item => {
        const badgeClass = `badge-${item.type}`;
        html += `
          <div class="timeline-item">
            <div class="timeline-time-col">
              <span class="item-time">${item.time}</span>
              <span class="item-type-badge ${badgeClass}">${item.type.toUpperCase()}</span>
            </div>
            <div class="timeline-details">
              <span class="item-title">${item.title}</span>
              <span class="item-note">${item.note}</span>
            </div>
          </div>
        `;
      });
      html += '</div>';
      windowBody.innerHTML = html;
    } else if (currentTabKey === 'summary') {
      let statsHtml = '';
      data.summary.stats.forEach(st => {
        statsHtml += `<div class="stat-pill"><span>${st.label}:</span> <strong>${st.val}</strong></div>`;
      });

      windowBody.innerHTML = `
        <div class="summary-block">
          <div class="greeting-card">
            <h3>${data.summary.greeting}</h3>
            <p>${data.summary.text}</p>
          </div>
          <div class="stat-pills-row">
            ${statsHtml}
          </div>
        </div>
      `;
    } else if (currentTabKey === 'sources') {
      let sourcesHtml = '<div class="sources-grid-preview">';
      data.sources.forEach(src => {
        sourcesHtml += `
          <div class="source-item-card">
            <div class="source-head">
              <span>${src.name}</span>
              <span class="source-badge">● Active</span>
            </div>
            <span style="font-size:0.86rem; color:#ffffff; font-weight:500;">${src.status}</span>
            <span class="source-desc">${src.desc}</span>
          </div>
        `;
      });
      sourcesHtml += '</div>';
      windowBody.innerHTML = sourcesHtml;
    }
  }

  // Scenario Pill Click Handler
  scenarioPills.forEach(pill => {
    pill.addEventListener('click', () => {
      scenarioPills.forEach(p => p.classList.remove('active'));
      pill.classList.add('active');
      currentScenarioKey = pill.getAttribute('data-scenario');
      renderWindow();
      if (isPlayingAudio) resetAudio();
    });
  });

  // Tab Button Click Handler
  tabBtns.forEach(tab => {
    tab.addEventListener('click', () => {
      tabBtns.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      currentTabKey = tab.getAttribute('data-tab');
      renderWindow();
    });
  });

  // Audio Playback Simulation
  function toggleAudio() {
    isPlayingAudio = !isPlayingAudio;
    if (isPlayingAudio) {
      audioToggle.innerHTML = '❚❚';
      audioWaves.classList.add('playing');
      listenHeroText.textContent = 'Pause Briefing Audio';
      audioTimer = setInterval(() => {
        elapsedSeconds++;
        const mins = Math.floor(elapsedSeconds / 60);
        const secs = (elapsedSeconds % 60).toString().padStart(2, '0');
        audioTime.textContent = `${mins}:${secs}`;
        if (elapsedSeconds >= 24) {
          resetAudio();
        }
      }, 1000);
    } else {
      resetAudio();
    }
  }

  function resetAudio() {
    isPlayingAudio = false;
    clearInterval(audioTimer);
    elapsedSeconds = 0;
    audioTime.textContent = '0:14';
    audioToggle.innerHTML = '▶';
    audioWaves.classList.remove('playing');
    listenHeroText.textContent = 'Listen to 8:00 AM Briefing';
  }

  audioToggle.addEventListener('click', toggleAudio);
  listenHeroBtn.addEventListener('click', () => {
    // Scroll smoothly to simulator and toggle audio
    document.getElementById('routine').scrollIntoView({ behavior: 'smooth' });
    if (!isPlayingAudio) {
      setTimeout(toggleAudio, 400);
    }
  });

  // Interactive Dynamic Island states on tap
  const islandStates = [
    { title: '8:00 AM · Summary Ready', desc: '3 meetings · 2 urgent emails · Plan ready' },
    { title: 'Listening to question...', desc: 'Microphone stream active' },
    { title: 'Reasoning with local AI...', desc: 'Apple Foundation Models' },
    { title: 'Speaking answer...', desc: '"Your 10:30 meeting is with Design"' }
  ];
  let islandIdx = 0;

  if (interactiveIsland) {
    interactiveIsland.addEventListener('click', () => {
      islandIdx = (islandIdx + 1) % islandStates.length;
      islandLabel.textContent = islandStates[islandIdx].title;
      lockDesc.textContent = islandStates[islandIdx].desc;
    });
  }

  // Mascot Cursor Interactive Tracking
  const heroAnchor = document.getElementById('hero-mascot-anchor');
  const heroMascot = document.getElementById('hero-mascot');

  if (heroAnchor && heroMascot) {
    window.addEventListener('mousemove', (e) => {
      const rect = heroAnchor.getBoundingClientRect();
      const anchorCenterX = rect.left + rect.width / 2;
      const anchorCenterY = rect.top + rect.height / 2;

      const deltaX = (e.clientX - anchorCenterX) / 35;
      const deltaY = (e.clientY - anchorCenterY) / 35;

      // Subtle clamp
      const clampedX = Math.max(-12, Math.min(12, deltaX));
      const clampedY = Math.max(-10, Math.min(10, deltaY));

      heroMascot.style.transform = `translate(${clampedX}px, ${clampedY}px)`;
    });
  }

  // Initial Render
  renderWindow();
});
