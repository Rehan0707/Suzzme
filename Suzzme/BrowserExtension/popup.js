import {inspectActiveIntegration, supportedIntegrationOrigins} from "./integration-connection.js";
import {inspectActiveRepository} from "./github-connection.js";

const status = document.querySelector("#status");
const buttons = [...document.querySelectorAll("button")].filter(button => button.id !== "request-github");
const autoDetectionButton = document.querySelector("#toggle-auto-detection");
const autoDetectionStatus = document.querySelector("#auto-detection-status");
const serviceNames = {github: "GitHub", linkedin: "LinkedIn", notion: "Notion", slack: "Slack"};
function show(message) { status.textContent = message; }
async function perform(message) {
  buttons.forEach(button => { button.disabled = true; });
  try {
    const response = await chrome.runtime.sendMessage(message);
    if (!response || typeof response.ok !== "boolean" || typeof response.message !== "string") {
      throw new Error("The browser extension did not return a valid result.");
    }
    show(response.message);
  } catch { show("The browser extension is unavailable. Reload it and try again."); }
  finally { buttons.forEach(button => { button.disabled = button.id.startsWith("share-"); }); }
}
async function refreshAutoDetection() {
  const [{autoIntegrationDetection = false, pairing}, granted] = await Promise.all([
    chrome.storage.local.get(["autoIntegrationDetection", "pairing"]),
    chrome.permissions.contains({origins: supportedIntegrationOrigins})
  ]);
  const enabled = autoIntegrationDetection && granted;
  if (autoIntegrationDetection && !granted) await chrome.storage.local.set({autoIntegrationDetection: false});
  autoDetectionButton.textContent = enabled ? "Turn off automatic tab prompts" : "Enable automatic tab prompts";
  autoDetectionStatus.textContent = enabled
    ? "On for supported HTTPS tabs. Only the active app name is checked."
    : "Off. Suzme will not monitor active app tabs until you enable this.";
  return enabled;
}

autoDetectionButton.addEventListener("click", async () => {
  autoDetectionButton.disabled = true;
  try {
    const enabled = await refreshAutoDetection();
    if (enabled) {
      await chrome.permissions.remove({origins: supportedIntegrationOrigins});
      await chrome.storage.local.set({autoIntegrationDetection: false});
      await chrome.runtime.sendMessage({method: "discovery.updated"});
      autoDetectionStatus.textContent = "Off. Supported-site permissions were removed.";
    } else {
      const granted = await chrome.permissions.request({origins: supportedIntegrationOrigins});
      if (!granted) {
        autoDetectionStatus.textContent = "Permission declined. You can still request a connection from this popup.";
        return;
      }
      await chrome.storage.local.set({autoIntegrationDetection: true});
      const response = await chrome.runtime.sendMessage({method: "discovery.updated"});
      autoDetectionStatus.textContent = response?.ok === true
        ? "On. Suzzme will ask before opening a connection setup."
        : "On. Pair this browser in Suzzme to receive connection prompts.";
    }
  } catch {
    autoDetectionStatus.textContent = "The setting could not be changed. Check this extension’s permissions and try again.";
  } finally {
    await refreshAutoDetection();
    autoDetectionButton.disabled = false;
  }
});

document.querySelector("#share-url").addEventListener("click", () => perform({method: "capture", mode: "url"}));
document.querySelector("#share-selection").addEventListener("click", () => perform({method: "capture", mode: "selection"}));
document.querySelector("#share-page").addEventListener("click", () => perform({method: "capture", mode: "page"}));
document.querySelector("#pairing-form").addEventListener("submit", async event => {
  event.preventDefault();
  const field = document.querySelector("#pairing-code");
  const token = field.value.trim(); field.value = "";
  await perform({method: "pair", pairingToken: token});
});
document.querySelector("#forget-pairing").addEventListener("click", () => perform({method: "forget"}));

const requestButton = document.querySelector("#request-github");
const githubStatus = document.querySelector("#github-status");
const integrationStatus = document.querySelector("#integration-status");
const integrationButton = document.querySelector("#request-integration");
let detectedIntegration;
let integrationRequestStarted = false;
let detectedRepository;
let githubRequestStarted = false;
requestButton.addEventListener("click", async () => {
  if (githubRequestStarted || !detectedRepository) return;
  githubRequestStarted = true; requestButton.disabled = true;
  try {
    const response = await chrome.runtime.sendMessage({method: "github.request", detected: detectedRepository});
    if (!response || response.ok !== true || typeof response.message !== "string") throw new Error(response?.message ?? "The native browser bridge is unavailable.");
    githubStatus.textContent = response.message;
  } catch (error) {
    githubStatus.textContent = error instanceof Error ? error.message : "Suzzme could not be opened. Reopen this popup to try again.";
  }
});
async function recognizeRepository() {
  try {
    detectedRepository = await inspectActiveRepository(chrome);
    if (detectedRepository) {
      githubStatus.textContent = detectedRepository.repository;
      requestButton.hidden = false;
      requestButton.setAttribute("aria-label", `Request ${detectedRepository.repository} in Suzzme`);
    } else { githubStatus.textContent = "This tab is not a supported GitHub repository page. Open a repository, then open this popup again."; }
  } catch { githubStatus.textContent = "This tab’s URL is unavailable. Open the popup on a regular GitHub repository page."; }
}
integrationButton.addEventListener("click", async () => {
  if (integrationRequestStarted || !detectedIntegration) return;
  integrationRequestStarted = true; integrationButton.disabled = true;
  try {
    const response = await chrome.runtime.sendMessage({method: "integration.request", service: detectedIntegration.service});
    if (!response || response.ok !== true || typeof response.message !== "string") throw new Error(response?.message ?? "The native browser bridge is unavailable.");
    integrationStatus.textContent = response.message;
  } catch (error) {
    integrationStatus.textContent = error instanceof Error ? error.message : "Suzzme could not be opened. Reopen this popup to try again.";
  }
});
async function recognizeIntegration() {
  try {
    detectedIntegration = await inspectActiveIntegration(chrome);
    if (detectedIntegration) {
      const name = serviceNames[detectedIntegration.service] ?? detectedIntegration.service;
      integrationStatus.textContent = `${name} tab detected`;
      integrationButton.hidden = false;
      integrationButton.textContent = `Request ${name} connection in Suzzme`;
    } else { integrationStatus.textContent = "No supported app tab detected. Supported tabs: GitHub, LinkedIn, Notion, and Slack."; }
  } catch { integrationStatus.textContent = "This tab’s app identity is unavailable. Open the extension on a supported HTTPS app tab."; }
}
await Promise.all([refreshAutoDetection(), recognizeIntegration(), recognizeRepository(), perform({method: "status"})]);
