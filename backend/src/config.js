// Tunable product rules. Everything the plan calls "configurable" lives here.
export const CONFIG = {
  eventThreshold: 5, // distinct supporters needed to turn an issue into an event
  verifyNeeded: 2, // approvals (or rejections) needed to settle a resolution
  duplicateRadiusKm: 0.2, // similar-issue lookup radius
  minNetaSample: 5, // issues needed before a resolution rate is shown
  maxSpeedKmh: 300, // location plausibility check
  defaultAlertRadiusKm: 5,
  stateFallbackKm: 250, // outside every city: resolve to the nearest city's state when it is within this distance, else 'all'
  scheduleDefaultDays: 3,
  // gatherings
  campaignVotes: 5, // votes that turn a proposal into an upcoming campaign
  checkinRadiusKm: 0.5,
  checkinEarlyMinutes: 30,
  checkinDefaultHours: 3, // gathering length when no endAt is given
  reminderMinutes: 60,
  // donations
  foodShelfHours: 4,
  otherShelfDays: 7,
  foodMaxAgeHours: 3, // food prepared longer ago than this cannot be listed
  claimLockMinutes: 45,
  claimEtaMinMinutes: 10,
  claimEtaMaxMinutes: 120,
  foundationAlertRadiusKm: 15,
  // media
  maxMediaMb: 12,
  bodyLimitMb: 20,
};

export const GATHERING_TYPES = {
  plantation: 'Plantation drive',
  animal_care: 'Animal care',
  shelter: 'Shelter & homes',
  marathon: 'Run / marathon',
  health: 'Health camp',
  cleanup: 'Clean-up drive',
  blood: 'Blood donation',
  food_drive: 'Food drive',
  other: 'Other',
};

export const DONATION_KINDS = {
  food: 'Food',
  clothes: 'Clothes',
  bottles: 'Bottles',
  books: 'Books',
  toys: 'Toys',
  essentials: 'Essentials',
  other: 'Other',
};

export const ROLES = ['citizen', 'admin', 'neta', 'foundation'];

// category -> responsible department (shown on every issue)
export const DEPARTMENTS = {
  road: 'Public Works',
  garbage: 'Solid Waste Management',
  water: 'Water Supply',
  drainage: 'Drainage & Sewerage',
  electricity: 'Electricity Department',
  streetlight: 'Street Lighting',
  safety: 'Public Safety',
  park: 'Parks & Gardens',
  other: 'General Administration',
};

// city -> civic body + social handle
export const CITY_AUTHORITIES = {
  Raipur: { name: 'Raipur Municipal Corporation', handle: '@RMC_Raipur' },
  Bilaspur: { name: 'Bilaspur Municipal Corporation', handle: '@BMC_Bilaspur' },
  'Bhilai-Durg': { name: 'Bhilai Municipal Corporation', handle: '@BhilaiMC' },
  Korba: { name: 'Korba Municipal Corporation', handle: '@KorbaMC' },
  Bhopal: { name: 'Bhopal Municipal Corporation', handle: '@BMC_Bhopal' },
  Bhubaneswar: { name: 'Bhubaneswar Municipal Corporation', handle: '@BMCBhubaneswar' },
};

export function authorityFor(cityName, category) {
  const c = CITY_AUTHORITIES[cityName] || {
    name: `${cityName || 'City'} Municipal Corporation`,
    handle: `@${String(cityName || 'City').replace(/[^A-Za-z]/g, '')}Civic`,
  };
  return { name: c.name, department: DEPARTMENTS[category] || DEPARTMENTS.other, handle: c.handle };
}

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
  rsvp: 5,
  checkin: 15,
  comment: 1,
  donationDonor: 10,
  donationFoundation: 5,
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
  { key: 'volunteer_heart', name: 'Volunteer Heart', desc: 'Check in at your first gathering', icon: 'heart' },
  { key: 'green_thumb', name: 'Green Thumb', desc: 'Check in at 3 plantation or clean-up drives', icon: 'plant' },
  { key: 'giver', name: 'Giver', desc: 'Have a donation distributed to people in need', icon: 'gift' },
  { key: 'feeder', name: 'Feeder', desc: 'Get 5 food donations distributed', icon: 'food' },
  { key: 'voice', name: 'Voice of the People', desc: 'Write 5 comments', icon: 'voice' },
];
