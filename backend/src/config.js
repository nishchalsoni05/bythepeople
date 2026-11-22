// Tunable product rules. Everything the plan calls "configurable" lives here.
export const CONFIG = {
  eventThreshold: 5, // distinct supporters needed to turn an issue into an event
  verifyNeeded: 2, // approvals (or rejections) needed to settle a resolution
  duplicateRadiusKm: 0.2, // similar-issue lookup radius
  minNetaSample: 5, // issues needed before a resolution rate is shown
  maxSpeedKmh: 300, // location plausibility check
  defaultAlertRadiusKm: 5,
  scheduleDefaultDays: 3,
};

// radius = how close you must be to report/support. weight feeds severity.
export const CATEGORIES = {
  road: { label: 'Roads & Potholes', radiusKm: 1, weight: 2, icon: 'road' },
  garbage: { label: 'Garbage & Waste', radiusKm: 1.5, weight: 2, icon: 'garbage' },
  water: { label: 'Water Supply', radiusKm: 3, weight: 4, icon: 'water' },
  drainage: { label: 'Drainage & Flooding', radiusKm: 2, weight: 3, icon: 'drainage' },
  electricity: { label: 'Electricity', radiusKm: 3, weight: 3, icon: 'electricity' },
  streetlight: { label: 'Street Lights', radiusKm: 1, weight: 1, icon: 'streetlight' },
  safety: { label: 'Public Safety', radiusKm: 2, weight: 4, icon: 'safety' },
  park: { label: 'Parks & Lakes', radiusKm: 1.5, weight: 1, icon: 'park' },
  other: { label: 'Other', radiusKm: 2, weight: 1, icon: 'other' },
};

export const RANKS = [
  { name: 'Recruit', min: 0 },
  { name: 'Scout', min: 50 },
  { name: 'Tracker', min: 150 },
  { name: 'Ranger', min: 350 },
  { name: 'Guardian', min: 700 },
  { name: 'Legend', min: 1200 },
];

export const POINTS = {
  report: 10,
  support: 3,
  join: 5,
  verify: 4,
  eventCreated: 15,
  closedReporter: 10,
  closedVolunteer: 20,
};

export const SEVERITY_WEIGHT = { low: 1, medium: 2, high: 3, critical: 4 };

export const BADGES = [
  { key: 'first_report', name: 'First Flag', desc: 'File your first report', icon: 'flag' },
  { key: 'first_support', name: 'Good Neighbour', desc: 'Support a neighbour\'s issue', icon: 'handshake' },
  { key: 'watchdog', name: 'Civic Watchdog', desc: 'Support 5 issues', icon: 'watchdog' },
  { key: 'town_crier', name: 'Town Crier', desc: 'File 5 reports', icon: 'megaphone' },
  { key: 'spark', name: 'Spark', desc: 'Have a report become an event', icon: 'spark' },
  { key: 'first_responder', name: 'First Responder', desc: 'Join an event as a volunteer', icon: 'responder' },
  { key: 'truth_seeker', name: 'Truth Seeker', desc: 'Verify 3 resolutions', icon: 'verify' },
  { key: 'hero', name: 'Neighbourhood Hero', desc: 'Help close an event', icon: 'hero' },
  { key: 'best_citizen', name: 'Best Citizen', desc: 'Reach 300 points', icon: 'crown' },
];
